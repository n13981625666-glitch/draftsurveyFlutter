import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_model.dart';
import '../core/constants.dart';
import '../core/util.dart';
import '../services/license.dart';
import '../services/pdf.dart';
import '../services/platform_io.dart';
import 'actions.dart';
import 'page_arrival_misc.dart';
import 'page_sounding.dart';
import 'page_stowage.dart';
import 'page_survey.dart';
import 'page_trimming.dart';
import 'theme.dart';
import 'widgets.dart';

const _surveyTabs = {'initial': 'Initial', 'int1': 'Int 1', 'int2': 'Int 2', 'final': 'Final'};
const _otherTabs = {
  'sounding': 'Sounding',
  'trimming': 'Trimming',
  'stowage': 'Stowage',
  'arrival': 'Arrival',
  'misc': 'Misc',
};

class MainShell extends StatefulWidget {
  final AppModel m;
  final LicenseService lic;
  final SharedPreferences prefs;
  final String? licensee;
  final bool dark;
  final VoidCallback onToggleTheme;
  const MainShell({
    super.key,
    required this.m,
    required this.lic,
    required this.prefs,
    required this.licensee,
    required this.dark,
    required this.onToggleTheme,
  });
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver implements AppActions {
  String tab = 'initial';
  final _scroll = <String, double>{};
  final _sc = ScrollController();
  Timer? _tipTimer, _tipHide;
  String? tip;
  final _rnd = Random();
  List<String> _bag = [];
  int _dialogs = 0;

  AppModel get m => widget.m;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    m.toast = (msg, kind, {ms}) {
      if (mounted) showToast(context, msg, kind, ms: ms);
    };
    m.pushShared = (data) async {
      await widget.lic.sync('/v1/sync/push', m.ship.id, data);
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _expiryWarning();
      _scheduleTip(first: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tipTimer?.cancel();
    _tipHide?.cancel();
    m.saveNow();
    m.toast = null;
    m.pushShared = null;
    _sc.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) m.saveNow();
  }

  void _expiryWarning() {
    final st = widget.lic.status();
    if (st.active && st.daysLeft <= 7 && mounted) {
      showToast(context, 'Licence expires in ${st.daysLeft < 0 ? 0 : st.daysLeft} day(s). Contact the vendor to renew.', ToastKind.warn, ms: 8000);
    }
  }

  // ------------------------------------------------------------------ tip bubble
  void _scheduleTip({bool first = false}) {
    _tipTimer?.cancel();
    if (m.ship.messages.isEmpty) return;
    final delay = first ? const Duration(minutes: 1) : Duration(seconds: 600 + _rnd.nextInt(1201));
    _tipTimer = Timer(delay, () {
      if (!mounted) return;
      if (_dialogs > 0) {
        _scheduleTip(first: true);
        return;
      }
      if (_bag.isEmpty) _bag = List.of(m.ship.messages)..shuffle(_rnd);
      setState(() => tip = _bag.removeLast());
      _tipHide?.cancel();
      _tipHide = Timer(const Duration(seconds: 45), () {
        if (mounted) setState(() => tip = null);
      });
      _scheduleTip();
    });
  }

  // ------------------------------------------------------------------ tabs
  void _go(String t) {
    _scroll[tab] = _sc.hasClients ? _sc.offset : 0;
    setState(() => tab = t);
    if (_surveyTabs.containsKey(t)) m.lastDraftSurveyTab = t;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sc.hasClients) _sc.jumpTo(min(_scroll[t] ?? 0, _sc.position.maxScrollExtent));
    });
  }

  Widget _page() {
    if (_surveyTabs.containsKey(tab)) return SurveyPage(m: m, actions: this, tab: tab);
    switch (tab) {
      case 'sounding':
        return SoundingPage(m: m, actions: this);
      case 'trimming':
        return TrimmingPage(m: m);
      case 'stowage':
        return StowagePage(m: m);
      case 'arrival':
        return ArrivalPage(m: m);
      default:
        return MiscPage(m: m);
    }
  }

  Widget _tabItem(Pal p, {required bool sel, required String label, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: sel ? p.accent : Colors.transparent, width: 3)),
      ),
      child: child,
    );
  }

  Widget _tabButton(Pal p, String id, String label) {
    final sel = tab == id;
    return InkWell(
      onTap: () => _go(id),
      child: _tabItem(p,
          sel: sel,
          label: label,
          child: Text(label,
              style: TextStyle(
                  color: sel ? p.accent : p.muted,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                  ))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final inSurvey = _surveyTabs.containsKey(tab);
    return Scaffold(
        body: Column(children: [
          Container(
            decoration: BoxDecoration(color: p.bar, border: Border(bottom: BorderSide(color: p.border))),
            child: SafeArea(
              bottom: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 2),
                      child: Row(children: [
                        Icon(Icons.directions_boat_filled, size: 22, color: p.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(m.ship.name.toUpperCase(),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: p.fg)),
                        ),
                        IconButton(tooltip: 'Licence', icon: Icon(Icons.verified_outlined, size: 22, color: p.muted), onPressed: _licenseInfo),
                        IconButton(
                          tooltip: 'Theme',
                          icon: Icon(widget.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 22, color: p.accent),
                          onPressed: widget.onToggleTheme,
                        ),
                      ]),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: SizedBox(
                        height: 42,
                        child: Row(children: [
                          PopupMenuButton<String>(
                            tooltip: 'Draft Survey',
                            onSelected: _go,
                            itemBuilder: (_) => [for (final e in _surveyTabs.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
                            child: _tabItem(p,
                                sel: inSurvey,
                                label: 'Draft Survey',
                                child: Row(children: [
                                  Text('Draft Survey${inSurvey ? ' · ${_surveyTabs[tab]}' : ''}',
                                      style: TextStyle(
                                          color: inSurvey ? p.accent : p.muted,
                                          fontWeight: inSurvey ? FontWeight.w700 : FontWeight.w500,
                                          fontSize: 14)),
                                  Icon(Icons.arrow_drop_down, size: 20, color: inSurvey ? p.accent : p.muted),
                                ])),
                          ),
                          for (final e in _otherTabs.entries) _tabButton(p, e.key, e.value),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          Expanded(child: Stack(children: [
          SafeArea(
            top: false,
            child: SingleChildScrollView(
              controller: _sc,
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(children: [
                    ListenableBuilder(
                      listenable: Listenable.merge([m, m.s]),
                      builder: (_, __) => _page(),
                    ),
                    _footer(p),
                  ]),
                ),
              ),
            ),
          ),
          if (tip != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Material(
                color: p.card,
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                  child: Row(children: [
                    Expanded(child: Text(tip!, style: TextStyle(color: p.fg))),
                    IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => tip = null)),
                  ]),
                ),
              ),
            ),
        ])),
        ]),
    );
  }

  Widget _footer(Pal p) {
    final small = TextStyle(color: p.muted, fontSize: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(children: [
        Text(
          "© Draft Survey V$appVersion — Use for estimation. Follow vessel's official hydro & stability book for certified figures.",
          textAlign: TextAlign.center,
          style: small,
        ),
        const SizedBox(height: 6),
        Wrap(alignment: WrapAlignment.center, spacing: 14, children: [
          InkWell(onTap: () => openExternal(contactWebsite), child: Text(contactWebsiteLabel, style: TextStyle(color: p.accent, fontSize: 12))),
          InkWell(onTap: _wechat, child: Text('WeChat', style: TextStyle(color: p.accent, fontSize: 12))),
          InkWell(onTap: () => openExternal('mailto:$contactEmail'), child: Text(contactEmail, style: TextStyle(color: p.accent, fontSize: 12))),
        ]),
      ]),
    );
  }

  Future<T?> _dialog<T>(WidgetBuilder b) async {
    _dialogs++;
    try {
      return await showDialog<T>(context: context, builder: b);
    } finally {
      _dialogs--;
    }
  }

  void _wechat() {
    _dialog<void>((c) => AlertDialog(
          title: const Text('WeChat'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/branding/wechat_qr.jpg', width: 220),
            const SizedBox(height: 8),
            SelectableText(contactWechat),
          ]),
          actions: [
            TextButton(onPressed: () => Clipboard.setData(const ClipboardData(text: contactWechat)), child: const Text('Copy ID')),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
          ],
        ));
  }

  void _licenseInfo() {
    final st = widget.lic.status();
    _dialog<void>((c) => AlertDialog(
          title: const Text('Licence'),
          content: SelectableText([
            if ((widget.licensee ?? '').isNotEmpty) 'Licensee: ${widget.licensee}',
            'Customer: ${st.customer}',
            'State: ${st.state}',
            'Days left: ${st.daysLeft}',
            'Machine code: ${st.machineCode}',
            'Ships: ${st.ships.join(', ')}',
            'Version: $appVersion',
          ].join('\n')),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(c);
                try {
                  final ok = await widget.lic.check();
                  if (mounted) showToast(context, ok ? 'Licence checked online.' : 'Could not reach the server.', ok ? ToastKind.success : ToastKind.warn);
                } catch (e) {
                  if (mounted) showToast(context, '$e', ToastKind.error);
                }
              },
              child: const Text('Check online'),
            ),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
          ],
        ));
  }

  // ------------------------------------------------------------------ AppActions
  String _errText(Object e) => e is LicenseError ? 'Licence/server: ${e.code}' : '$e';

  @override
  Future<void> exportData() async {
    try {
      final data = m.getSurveyExportData();
      final bytes = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(data)));
      final ok = await saveBytes('DraftSurvey-${safeFileName(m.ship.name)}-${ymdToday()}.json', bytes,
          label: 'JSON', mime: 'application/json');
      if (!ok) return;
      if (mounted) showToast(context, 'Data exported.', ToastKind.success);
      try {
        await m.pushShared?.call(data);
      } catch (_) {/* best effort */}
    } catch (e) {
      if (mounted) showToast(context, 'Export failed: ${_errText(e)}', ToastKind.error);
    }
  }

  @override
  Future<void> importData() async {
    List<dynamic> items = [];
    try {
      final v = await widget.lic.sync('/v1/sync/list', m.ship.id);
      items = (v['items'] as List?) ?? [];
    } catch (_) {}
    items = items.reversed.take(5).toList();
    String? fromFile;
    dynamic chosen;
    if (items.isEmpty) {
      fromFile = await pickTextFile();
      if (fromFile == null) return;
    } else {
      final pick = await _dialog<int>((c) => SimpleDialog(
            title: const Text('Import data'),
            children: [
              SimpleDialogOption(onPressed: () => Navigator.pop(c, -1), child: const Text('From a file…')),
              for (var i = 0; i < items.length; i++)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, i),
                  child: Text(_itemLabel(items[i])),
                ),
            ],
          ));
      if (pick == null) return;
      if (pick < 0) {
        fromFile = await pickTextFile();
        if (fromFile == null) return;
      } else {
        chosen = (items[pick] as Map)['data'];
      }
    }
    try {
      final data = chosen ?? jsonDecode(fromFile!);
      if (!mounted) return;
      final ok = await _dialog<bool>((c) => AlertDialog(
            title: const Text('Replace current data?'),
            content: const Text('Importing replaces everything currently entered.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Replace')),
            ],
          ));
      if (ok != true) return;
      m.setSurveyImportData(data);
      m.scheduleSave();
      if (mounted) showToast(context, 'Data imported.', ToastKind.success);
    } catch (e) {
      if (mounted) showToast(context, 'Import failed: ${_errText(e)}', ToastKind.error);
    }
  }

  String _itemLabel(dynamic it) {
    final mp = it as Map;
    var ts = (mp['ts'] is num) ? (mp['ts'] as num).toInt() : 0;
    if (ts > 0 && ts < 100000000000) ts *= 1000;
    final d = ts == 0 ? '' : DateTime.fromMillisecondsSinceEpoch(ts).toLocal().toString().substring(0, 16);
    final who = '${mp['customer'] ?? ''}${mp['mine'] == true ? ' (this device)' : ''}';
    return 'Shared $d  $who'.trim();
  }

  Future<Map<String, String>?> _reportInfoDialog() {
    final ri = m.reportInfo ?? {};
    String saved(String k) => '${ri[k] ?? widget.prefs.getString('ri_$k') ?? ''}';
    final voy = TextEditingController(text: saved('voyNo'));
    final cargo = TextEditingController(text: saved('cargo'));
    final port = TextEditingController(text: saved('port'));
    final date = TextEditingController(text: '${ri['date'] ?? ymdToday()}');
    Widget f(String l, TextEditingController c) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(controller: c, decoration: InputDecoration(labelText: l, border: const OutlineInputBorder())),
        );
    return _dialog<Map<String, String>>((c) => AlertDialog(
          title: const Text('Report information'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [f('VOY NO.', voy), f('CARGO', cargo), f('PORT', port), f('DATE', date)])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(c, {'voyNo': voy.text.trim(), 'cargo': cargo.text.trim(), 'port': port.text.trim(), 'date': date.text.trim()}),
              child: const Text('Export'),
            ),
          ],
        ));
  }

  @override
  Future<void> exportReport() async {
    try {
      final info = await _reportInfoDialog();
      if (info == null) return;
      m.reportInfo = Map<String, dynamic>.from(info);
      for (final k in ['voyNo', 'cargo', 'port']) {
        widget.prefs.setString('ri_$k', info[k] ?? '');
      }
      m.scheduleSave();
      final data = {...m.buildDraftSurveyReportData(), ...info};
      final bytes = buildDraftSurveyPdf(data);
      final date = (info['date'] ?? '').isEmpty ? ymdToday() : info['date']!;
      await saveBytes('DraftSurveyReport-${safeFileName(m.ship.name)}-$date.pdf', bytes, label: 'PDF', mime: 'application/pdf');
    } catch (e) {
      if (mounted) showToast(context, 'PDF export failed: ${_errText(e)}', ToastKind.error);
    }
  }

  @override
  Future<void> printSounding() async {
    try {
      final bytes = buildSoundingPdf(m.buildSoundingReportData());
      await saveBytes('BallastWaterSummary-${safeFileName(m.ship.name)}-${ymdToday()}.pdf', bytes, label: 'PDF', mime: 'application/pdf');
    } catch (e) {
      if (mounted) showToast(context, 'PDF export failed: ${_errText(e)}', ToastKind.error);
    }
  }
}
