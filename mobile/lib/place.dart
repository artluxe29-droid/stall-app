import 'package:flutter/material.dart';

import 'api.dart';
import 'main.dart';
import 'screens/account_setup.dart';
import 'theme.dart';
import 'widgets.dart';

/// Nigeria's states and their Local Government Areas, from the server (it checks them the same way).
class Areas {
  static Map<String, List<String>>? _cache;

  static Future<Map<String, List<String>>> load(Api api) async {
    if (_cache != null) return _cache!;
    final m = (await api.get('areas'))['areas'] as Map<String, dynamic>? ?? const {};
    return _cache = {for (final e in m.entries) e.key: (e.value as List).map((x) => x.toString()).toList()};
  }
}

/// What the person picked: a state and an area in it.
class Place {
  const Place(this.state, this.area);
  final String? state, area;
  bool get done => (state ?? '').isNotEmpty && (area ?? '').isNotEmpty;
  Map<String, dynamic> get body => {'state': state, 'area': area};
}

/// Two dropdowns: state, then area (Local Government Area). Areas come from a list, never free text.
class PlacePicker extends StatefulWidget {
  const PlacePicker({super.key, this.initial = const Place(null, null), required this.onChanged, this.errors = const {}});
  final Place initial;
  final ValueChanged<Place> onChanged;

  /// Server errors by field ('state' or 'area'), read when the form is checked.
  final Map<String, String> errors;
  @override
  State<PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<PlacePicker> {
  Future<Map<String, List<String>>>? _f;
  String? _state, _area;

  @override
  void initState() {
    super.initState();
    _state = widget.initial.state;
    _area = widget.initial.area;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= Areas.load(SessionScope.of(context).api);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, List<String>>>(
        future: _f,
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(children: [
                const Expanded(child: Text('Couldn\'t load the list of areas.', style: TextStyle(color: StallColors.red))),
                TextButton(onPressed: () => setState(() => _f = Areas.load(SessionScope.of(context).api)), child: const Text('Try again')),
              ]),
            );
          }
          final all = snap.data ?? const <String, List<String>>{};
          final states = all.keys.toList()..sort();
          final areas = [...?all[_state]]..sort();
          final st = states.contains(_state) ? _state : null, ar = areas.contains(_area) ? _area : null;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<String>(
              key: const Key('pl-state'),
              isExpanded: true,
              initialValue: st,
              decoration: InputDecoration(labelText: 'State', suffixIcon: snap.hasData ? null : const _Spin()),
              items: [for (final s in states) DropdownMenuItem(value: s, child: Text(s))],
              validator: (v) => widget.errors['state'] ?? (v == null ? 'Choose your state.' : null),
              onChanged: (v) {
                setState(() {
                  _state = v;
                  _area = null;
                });
                widget.onChanged(Place(_state, null));
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              // A new key per state, so the area resets when the state changes.
              key: Key('pl-area-$_state'),
              isExpanded: true,
              initialValue: ar,
              decoration: const InputDecoration(labelText: 'Area (Local Government Area)'),
              items: [for (final a in areas) DropdownMenuItem(value: a, child: Text(a))],
              validator: (v) => widget.errors['area'] ?? (v == null ? 'Choose your area.' : null),
              onChanged: _state == null
                  ? null
                  : (v) {
                      setState(() => _area = v);
                      widget.onChanged(Place(_state, v));
                    },
            ),
            const SizedBox(height: 14),
          ]);
        },
      );
}

class _Spin extends StatelessWidget {
  const _Spin();
  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
}

/// "Which area are you in?": set or change your state and area. Your listings and store move with you.
class PlaceScreen extends StatefulWidget {
  const PlaceScreen({super.key, this.prompt = false});

  /// Shown by itself to an account that has no area yet (with "Not now").
  final bool prompt;
  @override
  State<PlaceScreen> createState() => _PlaceScreenState();
}

class _PlaceScreenState extends State<PlaceScreen> {
  final _form = GlobalKey<FormState>();
  Place? _p;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final s = SessionScope.of(context);
    try {
      await s.api.post('me/place', _p!.body);
      await s.refresh();
      if (!mounted) return;
      toast(context, 'Saved. You\'ll see things for sale in ${_p!.area}.');
      Navigator.pop(context, true);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = SessionScope.of(context).user;
    final t = Theme.of(context).textTheme;
    _p ??= Place(u?.state.isEmpty ?? true ? null : u!.state, u?.area.isEmpty ?? true ? null : u!.area);
    return Scaffold(
      appBar: AppBar(title: Text(widget.prompt ? '' : 'My area')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), children: [
            Text('Which area are you in?', style: t.headlineMedium),
            const SizedBox(height: 8),
            Text('Stall shows you things for sale near you, and people nearby see what you sell. Your listings and store move with you.',
                style: t.bodyLarge?.copyWith(color: StallColors.muted)),
            const SizedBox(height: 20),
            PlacePicker(initial: _p!, onChanged: (p) => _p = p),
            if (_error != null)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: const TextStyle(color: StallColors.red))),
            FilledButton(
              key: const Key('pl-save'),
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('Save'),
            ),
            if (widget.prompt) TextButton(key: const Key('pl-later'), onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          ]),
        ),
      ),
    );
  }
}

/// Account → Student: pick or change your school, or say you're not a student any more.
/// Businesses can link the campus they're on or near the same way.
Future<void> openStudentSettings(BuildContext context) async {
  final s = SessionScope.of(context);
  final u = s.user;
  if (u == null) return;
  final hasSchool = u.school != null;
  final pick = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: StallColors.cream,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          key: const Key('st-pick'),
          leading: const Icon(Icons.school_outlined, color: StallColors.indigo),
          title: Text(hasSchool ? 'Change school' : (u.isVendor ? 'We\'re on or near a campus' : 'I\'m a student')),
          subtitle: Text(u.isVendor ? 'Students there see your business in their campus feed.' : 'Get your campus feed and the Student badge.'),
          onTap: () => Navigator.pop(ctx, 'pick'),
        ),
        if (hasSchool)
          ListTile(
            key: const Key('st-none'),
            leading: const Icon(Icons.logout_rounded, color: StallColors.red),
            title: Text(u.isVendor ? 'Not linked to a campus' : 'I\'m not a student any more'),
            subtitle: const Text('You keep your store, ratings and badges.'),
            onTap: () => Navigator.pop(ctx, 'none'),
          ),
      ]),
    ),
  );
  if (pick == null || !context.mounted) return;
  Map<String, dynamic>? body;
  if (pick == 'none') {
    body = {'none': true};
  } else {
    final c = await Navigator.of(context).push<SchoolChoice>(MaterialPageRoute(builder: (_) => const SchoolPickerScreen()));
    if (c == null) return;
    body = c.body;
  }
  try {
    await s.api.post('me/school', body);
    await s.refresh();
    if (context.mounted) toast(context, pick == 'none' ? 'Done. You\'re no longer linked to a school.' : 'Saved.');
  } on ApiError catch (e) {
    if (context.mounted) toast(context, e.message);
  }
}
