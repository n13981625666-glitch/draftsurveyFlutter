import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_model.dart';
import 'core/constants.dart';
import 'core/ship.dart';
import 'services/license.dart';
import 'services/platform_io.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DraftSurveyApp());
}

class DraftSurveyApp extends StatefulWidget {
  const DraftSurveyApp({super.key});
  @override
  State<DraftSurveyApp> createState() => _DraftSurveyAppState();
}

class _DraftSurveyAppState extends State<DraftSurveyApp> {
  bool dark = true;
  SharedPreferences? prefs;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        prefs = p;
        dark = p.getString('color-theme') != 'light';
      });
    });
  }

  void toggleTheme() {
    setState(() => dark = !dark);
    prefs?.setString('color-theme', dark ? 'dark' : 'light');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Draft Survey',
      debugShowCheckedModeBanner: false,
      theme: (dark ? Pal.darkPal : Pal.lightPal).toTheme(),
      home: prefs == null
          ? const Scaffold(body: SizedBox.shrink())
          : Boot(prefs: prefs!, dark: dark, onToggleTheme: toggleTheme),
    );
  }
}

/// Startup: licence check -> (gate) -> ship decrypt -> main shell.
class Boot extends StatefulWidget {
  final SharedPreferences prefs;
  final bool dark;
  final VoidCallback onToggleTheme;
  const Boot({super.key, required this.prefs, required this.dark, required this.onToggleTheme});
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  LicenseService? lic;
  AppModel? model;
  LicenseStatus? status;
  String? licensee;
  String? fatal;
  String progress = 'Starting…';
  Timer? _poll, _check;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _check?.cancel();
    model?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      final key = (await rootBundle.loadString('assets/keys/license_public.key')).trim();
      lic = await LicenseService.create(dir, key);
      setState(() => progress = 'Checking licence…');
      status = lic!.status();
      if (status!.active) {
        await _loadShip();
      }
      _timers();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => fatal = '$e');
    }
  }

  void _timers() {
    _poll?.cancel();
    _check?.cancel();
    // Re-evaluate the licence state every minute (expiry / revoke / clock rollback lock the UI).
    _poll = Timer.periodic(const Duration(seconds: 60), (_) {
      final st = lic?.status();
      if (st == null || !mounted) return;
      final wasActive = status?.active ?? false;
      if (st.active != wasActive || st.state != status?.state) {
        setState(() => status = st);
      }
    });
    Future<void> doCheck() async {
      final l = lic;
      if (l == null || !l.checkDue()) return;
      await l.check();
      if (mounted) setState(() => status = l.status());
    }

    Timer(const Duration(seconds: 8), doCheck);
    _check = Timer.periodic(const Duration(minutes: 10), (_) => doCheck());
  }

  Future<void> _loadShip() async {
    setState(() => progress = 'Loading ship data…');
    final l = lic!;
    final idx = jsonDecode(await rootBundle.loadString('assets/ships/index.json')) as List;
    String? lastErr;
    for (final f in idx) {
      final text = await rootBundle.loadString('assets/ships/$f');
      final env = jsonDecode(text) as Map<String, dynamic>;
      final id = env['id'] as String;
      if (!l.status().ships.contains(id)) {
        lastErr = 'ship_not_licensed';
        continue;
      }
      try {
        final plain = await l.openShip(text);
        final ship = shipFromProfile(jsonDecode(plain) as Map<String, dynamic>, id);
        licensee = env['licensee'] as String?;
        model?.dispose();
        final m = AppModel(ship);
        m.persist = (json) => widget.prefs.setString('surveyData', json);
        m.restoreSaved(widget.prefs.getString('surveyData'));
        model = m;
        return;
      } on ShipProfileError catch (e) {
        lastErr = e.message;
      } on LicenseError catch (e) {
        lastErr = e.code;
      }
    }
    throw 'No ship available: ${lastErr ?? 'none'}';
  }

  Future<void> _activated() async {
    final l = lic!;
    try {
      status = l.status();
      if (status!.active) await _loadShip();
    } catch (e) {
      fatal = '$e';
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    if (fatal != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.error_outline, color: p.err, size: 48),
              const SizedBox(height: 12),
              SelectableText(fatal!, textAlign: TextAlign.center, style: TextStyle(color: p.fg)),
              const SizedBox(height: 12),
              Btn('Retry', () {
                setState(() {
                  fatal = null;
                  progress = 'Starting…';
                });
                _start();
              }),
            ]),
          ),
        ),
      );
    }
    if (lic == null || status == null) return Splash(text: progress);
    if (!status!.active || model == null) {
      if (status!.active && model == null) return Splash(text: progress);
      return LicenseGate(lic: lic!, status: status!, onChanged: _activated);
    }
    return MainShell(
      m: model!,
      lic: lic!,
      prefs: widget.prefs,
      licensee: licensee,
      dark: widget.dark,
      onToggleTheme: widget.onToggleTheme,
    );
  }
}

class Splash extends StatelessWidget {
  final String text;
  const Splash({super.key, required this.text});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/branding/splash-icon.png', width: 96, height: 96),
          const SizedBox(height: 16),
          Text('Draft Survey', style: TextStyle(color: p.fg, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          SizedBox(width: 160, child: LinearProgressIndicator(color: p.accent)),
          const SizedBox(height: 10),
          Text(text, style: TextStyle(color: p.muted, fontSize: 12)),
        ]),
      ),
    );
  }
}

String licenseErrorText(String code) {
  switch (code) {
    case 'offline':
      return 'Cannot reach the licence server. Check the network connection and try again.';
    case 'invalid':
      return 'Invalid activation key.';
    case 'revoked':
      return 'This licence has been revoked.';
    case 'expired':
      return 'This licence has expired.';
    case 'device_limit':
      return 'Device limit reached for this key.';
    case 'bad_public_key':
      return 'This build has no valid licence public key.';
    case 'ship_not_licensed':
      return 'This ship is not covered by your licence.';
    default:
      return 'Licence error: $code';
  }
}

class LicenseGate extends StatefulWidget {
  final LicenseService lic;
  final LicenseStatus status;
  final Future<void> Function() onChanged;
  const LicenseGate({super.key, required this.lic, required this.status, required this.onChanged});
  @override
  State<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends State<LicenseGate> {
  final key = TextEditingController();
  bool busy = false;
  String? msg;

  @override
  void dispose() {
    key.dispose();
    super.dispose();
  }

  String get title {
    switch (widget.status.state) {
      case 'expired':
        return 'Licence expired';
      case 'revoked':
        return 'Licence revoked';
      case 'clock':
        return 'System clock problem';
      case 'needs_online':
        return 'Online check required';
      case 'invalid':
        return 'Licence invalid';
      default:
        return 'Activation required';
    }
  }

  Future<void> run(Future<void> Function() f) async {
    setState(() {
      busy = true;
      msg = null;
    });
    try {
      await f();
    } on LicenseError catch (e) {
      msg = licenseErrorText(e.code);
    } catch (e) {
      msg = '$e';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final st = widget.status;
    final canActivate = st.state == 'unactivated' || st.state == 'invalid' || st.state == 'expired';
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: CardBox(title: title, titleColor: p.accent, children: [
              Text('Machine code', style: TextStyle(color: p.muted, fontSize: 12)),
              Row(children: [
                Expanded(
                  child: SelectableText(st.machineCode,
                      style: TextStyle(color: p.fg, fontSize: 20, fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => Clipboard.setData(ClipboardData(text: st.machineCode)),
                ),
              ]),
              const SizedBox(height: 8),
              if (st.customer.isNotEmpty) Text('Licensee: ${st.customer}', style: TextStyle(color: p.fg)),
              if (st.state == 'revoked' || st.state == 'clock' || st.state == 'needs_online')
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    st.state == 'clock'
                        ? 'The system clock looks wrong. Correct the date/time, then check online.'
                        : st.state == 'needs_online'
                            ? 'Connect to the internet and check the licence online.'
                            : 'Contact the vendor.',
                    style: TextStyle(color: p.warn),
                  ),
                ),
              if (canActivate) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: key,
                  enabled: !busy,
                  decoration: const InputDecoration(labelText: 'Activation key', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Btn('Activate', () => run(() async {
                      await widget.lic.activate(key.text);
                      await widget.onChanged();
                    }), primary: true),
              ],
              const SizedBox(height: 6),
              Btn('Check online', () => run(() async {
                    await widget.lic.check();
                    await widget.onChanged();
                  })),
              if (busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
              if (msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(msg!, style: TextStyle(color: p.err))),
              const Divider(height: 28),
              Text('Contact', style: TextStyle(color: p.muted, fontSize: 12)),
              InkWell(
                onTap: () => openExternal(contactWebsite),
                child: Text(contactWebsiteLabel, style: TextStyle(color: p.accent)),
              ),
              SelectableText('WeChat: $contactWechat', style: TextStyle(color: p.fg)),
              SelectableText(contactEmail, style: TextStyle(color: p.fg)),
            ]),
          ),
        ),
      ),
    );
  }
}
