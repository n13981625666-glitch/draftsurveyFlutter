import 'package:flutter/widgets.dart';

/// Kinds of fields. They mirror the HTML elements of the original app (the ids are kept so that exported
/// data files and the shared server data stay compatible with the Tauri version).
enum FK { num, text, sel, chk, cell }

class FieldDef {
  final String id;
  final FK kind;
  final String def;
  final String section;
  final bool disabled; // statically disabled = calculated / ship property, never exported
  const FieldDef(this.id, this.kind, this.section, {this.def = '', this.disabled = false});
}

/// Holds the value of every field of every page, keyed by the original element id.
class FieldStore extends ChangeNotifier {
  final Map<String, FieldDef> defs = {};
  final Map<String, List<String>> options = {};
  final Map<String, String> _val = {};
  final Map<String, bool> _chk = {};
  final Map<String, TextEditingController> _ctl = {};

  /// Dynamic enabled/disabled rules (mode switches, toggles). Set by AppModel.
  bool Function(String id)? dynamicDisabled;

  /// Called after the USER edited a field (typing / picking / toggling).
  void Function(String id)? onUserEdit;

  void register(FieldDef d, {List<String>? opts}) {
    defs[d.id] = d;
    if (d.kind == FK.chk) {
      _chk.putIfAbsent(d.id, () => d.def == 'true');
    } else {
      _val.putIfAbsent(d.id, () => d.def);
    }
    if (opts != null) options[d.id] = opts;
  }

  bool has(String id) => defs.containsKey(id);

  bool isDisabled(String id) {
    final d = defs[id];
    if (d == null) return true;
    if (d.disabled) return true;
    return dynamicDisabled?.call(id) ?? false;
  }

  // ---- text ----
  String get(String id) {
    final c = _ctl[id];
    if (c != null) return c.text;
    return _val[id] ?? '';
  }

  /// Programmatic write. Number fields drop anything that is not a number (like <input type=number>).
  void set(String id, String v, {bool notify = false}) {
    final d = defs[id];
    if (d == null) return;
    if (d.kind == FK.num) {
      final t = v.trim();
      final n = double.tryParse(t);
      if (n == null || !n.isFinite) v = '';
    }
    _val[id] = v;
    final c = _ctl[id];
    if (c != null && c.text != v) c.text = v;
    if (notify) notifyListeners();
  }

  TextEditingController controller(String id) {
    return _ctl.putIfAbsent(id, () => TextEditingController(text: _val[id] ?? ''));
  }

  /// Called by the text widgets while the user types.
  void typed(String id) {
    _val[id] = _ctl[id]?.text ?? '';
    onUserEdit?.call(id);
  }

  // ---- select ----
  void select(String id, String v) {
    _val[id] = v;
    notifyListeners();
    onUserEdit?.call(id);
  }

  // ---- checkbox ----
  bool checked(String id) => _chk[id] ?? false;

  void setChecked(String id, bool v, {bool notify = false}) {
    _chk[id] = v;
    if (notify) notifyListeners();
  }

  void toggle(String id, bool v) {
    _chk[id] = v;
    notifyListeners();
    onUserEdit?.call(id);
  }

  void changed() => notifyListeners();

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }
}
