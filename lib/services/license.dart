import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';

/// Licensing (port of src-tauri/src/license.rs + ships.rs).
///
/// * Online ONCE: [activate] sends the licence key + machine hash to the licence server and receives a token
///   signed with the vendor's Ed25519 private key. It is verified offline with the public key bundled in
///   assets/keys/license_public.key and stored machine-bound (AES-GCM) in the app support directory.
/// * Afterwards the app runs offline; a background timer re-checks the server every [checkIntervalSecs].
/// * Expiry comes from the signed token, with a clock-rollback guard (`last_seen`).

const int checkIntervalSecs = 6 * 3600;
const int? offlineGraceDays = null;
const int clockToleranceSecs = 600;

class LicenseError implements Exception {
  final String code;
  LicenseError(this.code);
  @override
  String toString() => code;
}

class ShipGrant {
  final String id;
  final String key; // base64 AES-256 key
  ShipGrant(this.id, this.key);
}

class Claims {
  final int v;
  final String lic;
  final String customer;
  final String machine;
  final int issued;
  final int expires;
  final List<ShipGrant> ships;
  Claims(this.v, this.lic, this.customer, this.machine, this.issued, this.expires, this.ships);

  factory Claims.fromJson(Map<String, dynamic> j) => Claims(
        (j['v'] as num).toInt(),
        j['lic'] as String,
        j['customer'] as String,
        j['machine'] as String,
        (j['issued'] as num).toInt(),
        (j['expires'] as num).toInt(),
        (j['ships'] as List)
            .map((g) => ShipGrant((g as Map)['id'] as String, g['key'] as String))
            .toList(),
      );
}

/// state: active | unactivated | expired | revoked | invalid | clock | needs_online
class LicenseStatus {
  final String state;
  final String customer;
  final int daysLeft;
  final int expires;
  final List<String> ships;
  final String machineCode;
  final int lastCheck;
  const LicenseStatus(this.state, this.customer, this.daysLeft, this.expires, this.ships, this.machineCode, this.lastCheck);
  bool get active => state == 'active';
}

class _Store {
  String? token;
  int lastSeen = 0;
  int lastCheck = 0;
  String? blocked;

  Map<String, dynamic> toJson() =>
      {'token': token, 'last_seen': lastSeen, 'last_check': lastCheck, 'blocked': blocked};

  static _Store fromJson(Map<String, dynamic> j) {
    final s = _Store();
    s.token = j['token'] as String?;
    s.lastSeen = (j['last_seen'] as num?)?.toInt() ?? 0;
    s.lastCheck = (j['last_check'] as num?)?.toInt() ?? 0;
    s.blocked = j['blocked'] as String?;
    return s;
  }
}

int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _b64urlDecode(String s) => Uint8List.fromList(base64Url.decode(base64Url.normalize(s)));

/// Desktop: OS machine id (same sources as the Rust `machine_uid` crate, so existing activations stay valid).
/// Mobile: random id created on first run (lost on reinstall -> ask the vendor to reset devices).
Future<String> _rawMachineId(Directory dir) async {
  try {
    if (Platform.isWindows) {
      final r = await Process.run('reg', ['query', r'HKLM\SOFTWARE\Microsoft\Cryptography', '/v', 'MachineGuid']);
      final m = RegExp(r'MachineGuid\s+REG_SZ\s+(\S+)').firstMatch('${r.stdout}');
      if (m != null) return m.group(1)!;
    } else if (Platform.isMacOS) {
      final r = await Process.run('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice']);
      final m = RegExp(r'"IOPlatformUUID"\s*=\s*"([^"]+)"').firstMatch('${r.stdout}');
      if (m != null) return m.group(1)!;
    } else if (Platform.isLinux) {
      for (final p in ['/var/lib/dbus/machine-id', '/etc/machine-id']) {
        final f = File(p);
        if (await f.exists()) {
          final t = (await f.readAsString()).trim();
          if (t.isNotEmpty) return t;
        }
      }
    }
  } catch (_) {
    // fall through to the install id
  }
  final f = File('${dir.path}/install_id');
  try {
    if (await f.exists()) {
      final t = (await f.readAsString()).trim();
      if (t.isNotEmpty) return t;
    }
  } catch (_) {}
  final rnd = Random.secure();
  final id = _hex(List<int>.generate(16, (_) => rnd.nextInt(256)));
  try {
    await f.writeAsString(id);
  } catch (_) {}
  return id;
}

class LicenseService {
  final Directory dir;
  final String machine;
  final Uint8List publicKey;
  _Store _store = _Store();
  Claims? _claims; // verified claims of _store.token
  Future<void> _io = Future.value();

  LicenseService._(this.dir, this.machine, this.publicKey);

  static Future<LicenseService> create(Directory dir, String publicKeyB64) async {
    await dir.create(recursive: true);
    final raw = await _rawMachineId(dir);
    final digest = await Sha256().hash(utf8.encode('draftsurvey|$raw'));
    Uint8List pk;
    try {
      pk = Uint8List.fromList(base64.decode(publicKeyB64.trim()));
    } catch (_) {
      pk = Uint8List(0);
    }
    final svc = LicenseService._(dir, _hex(digest.bytes), pk);
    await svc._load();
    return svc;
  }

  String get machineCode => machine.substring(0, 12).toUpperCase();
  File get _file => File('${dir.path}/license.bin');

  Future<SecretKey> _cipherKey() async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: SecretKey(utf8.encode(machine)),
      nonce: utf8.encode('draftsurvey-store-v1'),
      info: utf8.encode('license-store'),
    );
  }

  /// token = base64url(payload JSON) "." base64url(Ed25519 signature over the payload bytes)
  Future<Claims> verifyToken(String token) async {
    final parts = token.split('.');
    if (parts.length != 2) throw LicenseError('invalid');
    if (publicKey.length != 32) throw LicenseError('bad_public_key');
    try {
      final payload = _b64urlDecode(parts[0]);
      final sig = _b64urlDecode(parts[1]);
      final ok = await Ed25519().verify(
        payload,
        signature: Signature(sig, publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519)),
      );
      if (!ok) throw LicenseError('invalid');
      return Claims.fromJson(jsonDecode(utf8.decode(payload)) as Map<String, dynamic>);
    } on LicenseError {
      rethrow;
    } catch (_) {
      throw LicenseError('invalid');
    }
  }

  Future<void> _load() async {
    _store = _Store();
    _claims = null;
    try {
      final f = _file;
      if (await f.exists()) {
        final raw = await f.readAsBytes();
        if (raw.length > 12) {
          final box = SecretBox.fromConcatenation(raw, nonceLength: 12, macLength: 16);
          final plain = await AesGcm.with256bits().decrypt(box, secretKey: await _cipherKey());
          _store = _Store.fromJson(jsonDecode(utf8.decode(plain)) as Map<String, dynamic>);
        }
      }
    } catch (_) {
      _store = _Store(); // missing / unreadable / copied from another machine = empty
    }
    await _verifyStoredToken();
  }

  Future<void> _verifyStoredToken() async {
    _claims = null;
    final t = _store.token;
    if (t == null) return;
    try {
      _claims = await verifyToken(t);
    } catch (_) {
      _claims = null;
    }
  }

  Future<void> _save() {
    // serialise writes
    _io = _io.then((_) async {
      try {
        final key = await _cipherKey();
        final aes = AesGcm.with256bits();
        final box = await aes.encrypt(utf8.encode(jsonEncode(_store.toJson())), secretKey: key);
        final tmp = File('${dir.path}/license.bin.tmp');
        await tmp.writeAsBytes(box.concatenation(), flush: true);
        await tmp.rename(_file.path);
      } catch (_) {}
    });
    return _io;
  }

  LicenseStatus _empty(String state) =>
      LicenseStatus(state, '', 0, 0, const [], machineCode, _store.lastCheck);

  (LicenseStatus, Claims?) _evaluate() {
    final blocked = _store.blocked;
    if (blocked != null) {
      final state = blocked == 'expired' ? 'expired' : (blocked == 'revoked' ? 'revoked' : 'invalid');
      return (_empty(state), null);
    }
    if (_store.token == null) return (_empty('unactivated'), null);
    final c = _claims;
    if (c == null || c.machine != machine || c.v != 1) return (_empty('invalid'), null);

    final t = _now();
    final daysLeft = (((c.expires - t) < 0 ? 0 : (c.expires - t)) + 86399) ~/ 86400;
    LicenseStatus st(String state, int days) =>
        LicenseStatus(state, c.customer, days, c.expires, c.ships.map((g) => g.id).toList(), machineCode, _store.lastCheck);

    if (t + clockToleranceSecs < _store.lastSeen || t + clockToleranceSecs < c.issued) return (st('clock', daysLeft), null);
    if (t >= c.expires) return (st('expired', 0), null);
    if (offlineGraceDays != null && t - _store.lastCheck > offlineGraceDays! * 86400) {
      return (st('needs_online', daysLeft), null);
    }
    return (st('active', daysLeft), c);
  }

  /// Current status; also advances the clock-rollback watermark.
  LicenseStatus status() {
    final (st, _) = _evaluate();
    final t = _now();
    if (_store.token != null && t > _store.lastSeen + 60 && st.state != 'clock') {
      _store.lastSeen = t;
      _save();
    }
    return st;
  }

  /// Verified claims, or the state name as an error (used before decrypting ship data).
  Claims requireActive() {
    final (st, c) = _evaluate();
    if (c == null) throw LicenseError(st.state);
    return c;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body, int timeoutSecs) async {
    try {
      final resp = await http
          .post(
            Uri.parse('${licenseServerUrl.replaceAll(RegExp(r'/+$'), '')}$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(Duration(seconds: timeoutSecs));
      if (resp.statusCode >= 500) throw LicenseError('offline');
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } on LicenseError {
      rethrow;
    } catch (_) {
      throw LicenseError('offline');
    }
  }

  /// First-time activation. Errors: offline | invalid | revoked | expired | device_limit | bad_public_key
  Future<LicenseStatus> activate(String key) async {
    final reply = await _post('/v1/activate', {'key': key.trim(), 'machine': machine, 'app': appVersion}, 12);
    final replyStatus = reply['status'];
    if (replyStatus != 'ok') throw LicenseError('$replyStatus');
    final token = reply['token'];
    if (token is! String) throw LicenseError('invalid');
    final claims = await verifyToken(token);
    if (claims.machine != machine) throw LicenseError('invalid');
    final t = _now();
    _store = _Store()
      ..token = token
      ..lastSeen = t
      ..lastCheck = t;
    _claims = claims;
    await _save();
    return status();
  }

  /// Ask the server whether the licence is still valid. true = server answered, false = nothing to check / offline.
  Future<bool> check() async {
    final token = _store.token;
    if (token == null || _store.blocked != null) return false;
    Claims claims;
    try {
      claims = await verifyToken(token);
    } catch (_) {
      return false;
    }
    Map<String, dynamic> reply;
    try {
      reply = await _post('/v1/check', {'key': claims.lic, 'machine': machine}, 12);
    } catch (_) {
      return false;
    }
    final status = '${reply['status']}';
    switch (status) {
      case 'ok':
        final nt = reply['token'];
        if (nt is String) {
          try {
            final c = await verifyToken(nt);
            if (c.machine == machine) {
              _store.token = nt;
              _claims = c;
            }
          } catch (_) {}
        }
        _store.lastCheck = _now();
        break;
      case 'revoked':
      case 'invalid':
      case 'expired':
        _store.blocked = status;
        _store.token = null;
        _claims = null;
        _store.lastCheck = _now();
        break;
      default:
        return false;
    }
    await _save();
    return true;
  }

  bool checkDue() => _store.token != null && _now() - _store.lastCheck >= checkIntervalSecs;

  /// Shared survey data: POST { token, ship, data? } to a /v1/sync/* route. Best effort; throws on any trouble.
  Future<Map<String, dynamic>> sync(String path, String ship, [List<dynamic>? data]) async {
    final claims = requireActive();
    if (!claims.ships.any((g) => g.id == ship)) throw LicenseError('ship_not_licensed');
    final token = _store.token;
    if (token == null) throw LicenseError('invalid');
    final body = <String, dynamic>{'token': token, 'ship': ship};
    if (data != null) body['data'] = data;
    final v = await _post(path, body, 10);
    final st = v['status'];
    if (st == 'ok') return v;
    throw LicenseError(st is String ? st : 'offline');
  }

  // ------------------------------------------------------------------ ships (.shipx)
  /// Decrypt one envelope with the key granted by the (already verified) licence claims.
  /// Envelope: { v:1, id, name, nonce:b64(12), data:b64(ciphertext||tag) }; AES-256-GCM, AAD = ship id.
  Future<String> openShip(String envelopeJson) async {
    final claims = requireActive();
    Map<String, dynamic> env;
    try {
      env = jsonDecode(envelopeJson) as Map<String, dynamic>;
    } catch (_) {
      throw LicenseError('bad_ship_file');
    }
    if (env['v'] != 1 || env['id'] is! String) throw LicenseError('bad_ship_file');
    final id = env['id'] as String;
    ShipGrant? grant;
    for (final g in claims.ships) {
      if (g.id == id) grant = g;
    }
    if (grant == null) throw LicenseError('ship_not_licensed');
    Uint8List key, nonce, data;
    try {
      key = Uint8List.fromList(base64.decode(grant.key));
      nonce = Uint8List.fromList(base64.decode('${env['nonce']}'));
      data = Uint8List.fromList(base64.decode('${env['data']}'));
    } catch (_) {
      throw LicenseError('bad_ship_file');
    }
    if (key.length != 32 || nonce.length != 12 || data.length < 16) throw LicenseError('bad_ship_file');
    try {
      return await _decryptInIsolate(key, nonce, data, utf8.encode(id));
    } catch (_) {
      throw LicenseError('ship_decrypt_failed');
    }
  }
}

Future<String> _decryptInIsolate(Uint8List key, Uint8List nonce, Uint8List data, List<int> aad) {
  return Isolate.run(() => decryptShipBytes(key, nonce, data, aad));
}

/// Runs in a background isolate (decrypting a few MB in pure Dart takes a moment).
Future<String> decryptShipBytes(Uint8List key, Uint8List nonce, Uint8List ctAndTag, List<int> aad) async {
  final box = SecretBox(
    ctAndTag.sublist(0, ctAndTag.length - 16),
    nonce: nonce,
    mac: Mac(ctAndTag.sublist(ctAndTag.length - 16)),
  );
  final plain = await AesGcm.with256bits().decrypt(box, secretKey: SecretKey(key), aad: aad);
  return utf8.decode(plain);
}
