import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../main.dart';
import '../models.dart';
import '../place.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';

/// The same phone rule as the server and web app: an 11-digit Nigerian mobile number that isn't obviously made up.
String? phoneError(String v) {
  var d = v.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('234') && d.length == 13) d = '0${d.substring(3)}';
  if (!RegExp(r'^0[789][01]\d{8}$').hasMatch(d)) return 'Enter your 11-digit WhatsApp number, like 0803 123 4567.';
  final t = d.substring(3);
  if (RegExp(r'(\d)\1{6,}').hasMatch(t) || '01234567890123456789'.contains(t) || '98765432109876543210'.contains(t)) {
    return 'That doesn\'t look like a real number. Enter the one buyers and sellers can reach you on.';
  }
  return null;
}

final emailRule = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

Future<void> openLink(String path) => launchUrl(Uri.parse('$apiBase$path'), mode: LaunchMode.externalApplication);

class School {
  School(this.raw);
  final Map<String, dynamic> raw;
  int get id => (raw['id'] as num).toInt();
  String get name => (raw['name'] ?? '').toString();
  String get short => (raw['short'] ?? '').toString();
  String get state => (raw['state'] ?? '').toString();
  String get label => '$name${short.isEmpty ? '' : ' ($short)'}';
  bool matches(String q) {
    final s = q.toLowerCase().trim();
    return s.isEmpty || name.toLowerCase().contains(s) || short.toLowerCase().contains(s) || state.toLowerCase().contains(s);
  }
}

/// What the person picked: a school from the list, or the name and state of one that isn't listed yet.
class SchoolChoice {
  const SchoolChoice.listed(School this.school) : newName = null, newState = null;
  const SchoolChoice.unlisted(String this.newName, String this.newState) : school = null;
  final School? school;
  final String? newName;
  final String? newState;
  String get label => school?.label ?? '$newName — $newState';
  Map<String, dynamic> get body => school != null ? {'school_id': school!.id} : {'school_name': newName, 'school_state': newState};
}

/// A form field that opens a searchable list of schools (with "My school isn't on the list").
class SchoolField extends FormField<SchoolChoice> {
  SchoolField({super.key, super.onSaved, required ValueChanged<SchoolChoice> onPicked})
      : super(
          validator: (v) => v == null ? 'Choose your school.' : null,
          builder: (state) {
            final ctx = state.context;
            return InkWell(
              key: const Key('school'),
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                final c = await Navigator.of(ctx).push<SchoolChoice>(MaterialPageRoute(builder: (_) => const SchoolPickerScreen()));
                if (c != null) {
                  state.didChange(c);
                  if (state.hasError) state.validate();
                  onPicked(c);
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Your school',
                  errorText: state.errorText,
                  suffixIcon: const Icon(Icons.expand_more_rounded),
                ),
                isEmpty: state.value == null,
                child: Text(state.value?.label ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            );
          },
        );
}

class SchoolPickerScreen extends StatefulWidget {
  const SchoolPickerScreen({super.key});
  @override
  State<SchoolPickerScreen> createState() => _SchoolPickerScreenState();
}

class _SchoolPickerScreenState extends State<SchoolPickerScreen> {
  Future<Map<String, dynamic>>? _f;
  String _q = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= SessionScope.of(context).api.get('schools');
  }

  Future<void> _unlisted(List<String> states) async {
    final c = await showModalBottomSheet<SchoolChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: StallColors.cream,
      builder: (_) => _NewSchoolSheet(states: states, initial: _q),
    );
    if (c != null && mounted) Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Choose your school')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snap.hasError) {
              return EmptyState(
                icon: Icons.wifi_off_rounded,
                title: 'Couldn\'t load schools',
                text: snap.error is ApiError ? (snap.error as ApiError).message : 'Check your connection and try again.',
              );
            }
            final all = (snap.data!['schools'] as List? ?? const []).map((e) => School(e as Map<String, dynamic>)).toList();
            final states = (snap.data!['states'] as List? ?? const []).map((e) => e.toString()).toList();
            final hits = all.where((s) => s.matches(_q)).take(80).toList();
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: TextField(
                  key: const Key('schoolSearch'),
                  autofocus: true,
                  onChanged: (v) => setState(() => _q = v),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'e.g. UNILAG or Yaba Tech'),
                ),
              ),
              Expanded(
                child: ListView(children: [
                  for (final s in hits)
                    ListTile(
                      title: Text(s.label),
                      subtitle: Text(s.state),
                      onTap: () => Navigator.pop(context, SchoolChoice.listed(s)),
                    ),
                  ListTile(
                    key: const Key('notListed'),
                    leading: Icon(Icons.add_rounded, color: StallColors.indigo),
                    title: Text('My school isn\'t on the list', style: TextStyle(color: StallColors.indigo, fontWeight: FontWeight.w700)),
                    subtitle: const Text('We\'ll add it after a quick check. You can use Stall straight away.'),
                    onTap: () => _unlisted(states),
                  ),
                ]),
              ),
            ]);
          },
        ),
      );
}

class _NewSchoolSheet extends StatefulWidget {
  const _NewSchoolSheet({required this.states, required this.initial});
  final List<String> states;
  final String initial;
  @override
  State<_NewSchoolSheet> createState() => _NewSchoolSheetState();
}

class _NewSchoolSheetState extends State<_NewSchoolSheet> {
  late final _name = TextEditingController(text: widget.initial);
  String? _state;
  String? _err;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Add your school', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          TextField(
              key: const Key('newSchoolName'),
              controller: _name,
              maxLength: 90,
              decoration: const InputDecoration(labelText: 'Full name of your school')),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: const Key('newSchoolState'),
            initialValue: _state,
            decoration: const InputDecoration(labelText: 'State'),
            items: [for (final s in widget.states) DropdownMenuItem(value: s, child: Text(s))],
            onChanged: (v) => setState(() => _state = v),
          ),
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: const TextStyle(color: StallColors.red))),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('newSchoolSave'),
            onPressed: () {
              final n = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
              if (n.length < 4) return setState(() => _err = 'Type the full name of your school.');
              if (_state == null) return setState(() => _err = 'Choose the state your school is in.');
              Navigator.pop(context, SchoolChoice.unlisted(n, _state!));
            },
            child: const Text('Use this school'),
          ),
        ]),
      );
}

/// Create an account: personal (anyone; students also pick their school) or a business (a campus is optional).
/// Everyone picks their state and area.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _c = {for (final k in ['name', 'email', 'phone', 'pw', 'where', 'biz', 'code', 'ref']) k: TextEditingController()};
  bool _vendor = false, _student = false, _campus = false, _ok = false, _hide = true, _busy = false, _okErr = false, _tried = false;
  String _cat = Category.all.first.id;
  SchoolChoice? _school;
  Place _place = const Place(null, null);

  /// Students must pick their school; a business only if it's on or near a campus.
  bool get _needSchool => _vendor ? _campus : _student;
  final _serverErr = <String, String>{};
  String? _error;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String v(String k) => _c[k]!.text.trim();

  Future<void> _submit() async {
    setState(() {
      _serverErr.clear();
      _error = null;
      _okErr = !_ok;
      _tried = true;
    });
    final valid = _form.currentState!.validate();
    if (!valid || !_ok) return;
    setState(() => _busy = true);
    final s = SessionScope.of(context);
    try {
      await s.signUp({
        if (_needSchool) ..._school!.body,
        'role': _vendor ? 'vendor' : (_student ? 'student' : 'member'),
        ..._place.body,
        'name': v('name'),
        'phone': v('phone'),
        if (_vendor || _student) 'where': v('where'),
        'password': _c['pw']!.text,
        if (v('ref').isNotEmpty) 'ref': v('ref').toUpperCase(),
        if (_vendor) ...{'biz': v('biz'), 'cat': _cat, 'code': v('code')} else ...{'email': v('email')},
      });
      if (!mounted) return;
      // Back to the app (now signed in), then confirm their email.
      final nav = Navigator.of(context);
      nav.popUntil((r) => r.isFirst);
      final u = s.user;
      if (u != null && s.emailOn && u.email.isNotEmpty && !u.emailVerified) {
        nav.push(MaterialPageRoute(builder: (_) => const FinishSetupScreen()));
      }
    } on ApiError catch (e) {
      final field = e.data['field']?.toString();
      setState(() {
        if (field != null && field != 'school') {
          _serverErr[field] = e.message;
          _form.currentState!.validate();
        } else {
          _error = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String k, String label,
      {String? hint, TextInputType? kb, bool caps = false, int? max, String? Function(String)? check, List<String>? auto, bool pw = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
          key: Key('su-$k'),
          controller: _c[k],
          keyboardType: kb,
          obscureText: pw && _hide,
          maxLength: max,
          autofillHints: auto,
          textCapitalization: caps ? TextCapitalization.characters : (k == 'name' || k == 'biz' ? TextCapitalization.words : TextCapitalization.none),
          textInputAction: TextInputAction.next,
          onChanged: (_) => _serverErr.remove(k == 'pw' ? 'pw' : k),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            counterText: '',
            suffixIcon: pw
                ? IconButton(
                    tooltip: _hide ? 'Show password' : 'Hide password',
                    icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _hide = !_hide),
                  )
                : null,
          ),
          validator: (x) => _serverErr[k] ?? check?.call((x ?? '').trim()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Form(
            key: _form,
            // After the first try, each field re-checks as you fix it, so old errors don't linger.
            autovalidateMode: _tried ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Create your account', style: t.displaySmall),
              const SizedBox(height: 8),
              Text('Buy and sell safely with people near you, anywhere in Nigeria.', style: t.bodyLarge?.copyWith(color: StallColors.muted)),
              const SizedBox(height: 20),
              SegmentedButton<bool>(
                key: const Key('role'),
                segments: const [
                  ButtonSegment(value: false, label: Text('Personal'), icon: Icon(Icons.person_outline)),
                  ButtonSegment(value: true, label: Text('Business'), icon: Icon(Icons.storefront_outlined)),
                ],
                selected: {_vendor},
                onSelectionChanged: (x) => setState(() => _vendor = x.first),
              ),
              const SizedBox(height: 20),
              if (_vendor) ...[
                _field('biz', 'Business name', max: 40, check: (x) => x.length < 2 ? 'Enter your business name.' : null),
                _field('name', 'Owner\'s full name', max: 50, auto: const [AutofillHints.name], check: (x) => x.length < 3 ? 'Enter your full name.' : null),
              ] else ...[
                _field('name', 'Full name', max: 50, auto: const [AutofillHints.name], check: (x) => x.length < 3 ? 'Enter your full name.' : null),
                _field('email', 'Email address',
                    hint: 'you@gmail.com',
                    kb: TextInputType.emailAddress,
                    auto: const [AutofillHints.email],
                    check: (x) => emailRule.hasMatch(x) ? null : 'Enter a valid email address.'),
              ],
              _field('phone', 'WhatsApp number',
                  hint: '0803 123 4567', kb: TextInputType.phone, auto: const [AutofillHints.telephoneNumber], check: phoneError),
              _field('pw', 'Create a password',
                  hint: 'At least 8 characters',
                  pw: true,
                  auto: const [AutofillHints.newPassword],
                  check: (_) => _c['pw']!.text.length < 8 ? 'Use at least 8 characters.' : null),
              PlacePicker(
                errors: _serverErr,
                onChanged: (p) => setState(() {
                  _place = p;
                  _serverErr.remove('state');
                  _serverErr.remove('area');
                }),
              ),
              CheckboxListTile(
                key: const Key('su-student'),
                value: _vendor ? _campus : _student,
                onChanged: (x) => setState(() => _vendor ? _campus = x ?? false : _student = x ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(_vendor ? 'We\'re on or near a campus' : 'I\'m a student'),
                subtitle: Text(_vendor ? 'Students there see you in their campus feed.' : 'Get your campus feed and the Student badge.'),
              ),
              if (_needSchool) ...[
                SchoolField(key: ValueKey(_vendor), onPicked: (c) => _school = c),
                const SizedBox(height: 14),
              ],
              if (_vendor) ...[
                _field('where', 'Shop location',
                    hint: _campus ? 'e.g. Cafeteria, Stall 4' : 'e.g. Bodija Market, Shop 12',
                    max: 40,
                    check: (x) => x.length < 3 ? 'Where is your shop? A street, market or landmark is fine.' : null),
                DropdownButtonFormField<String>(
            isExpanded: true,
                  key: const Key('su-cat'),
                  initialValue: _cat,
                  decoration: const InputDecoration(labelText: 'What you sell'),
                  items: [for (final c in Category.all) DropdownMenuItem(value: c.id, child: Text(c.name))],
                  onChanged: (x) => setState(() => _cat = x ?? _cat),
                ),
                const SizedBox(height: 14),
                _field('code', 'Invite code (optional)', hint: 'Only if the Stall team gave you one', caps: true, max: 20),
              ] else if (_student)
                _field('where', 'Hostel or where you stay',
                    hint: 'e.g. Hall B, Room 214',
                    max: 40,
                    check: (x) => x.length < 2 ? 'Enter your hostel or where you stay, so buyers and sellers can meet you.' : null),
              _field('ref', 'Friend\'s invite code (optional)', hint: 'If a friend invited you', caps: true, max: 12),
              CheckboxListTile(
                key: const Key('su-ok'),
                value: _ok,
                onChanged: (x) => setState(() {
                  _ok = x ?? false;
                  if (_ok) _okErr = false;
                }),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(_vendor
                    ? 'I\'m 16 or older, I run this business, these details are correct, and I agree to the Terms and Privacy Policy.'
                    : 'I\'m 16 or older${_student ? ', I\'m a current student at the school above' : ''}, these details are correct, and I agree to the Terms and Privacy Policy.'),
                subtitle: _okErr ? const Text('Please confirm to continue.', style: TextStyle(color: StallColors.red)) : null,
              ),
              Wrap(spacing: 4, children: [
                TextButton(onPressed: () => openLink('/terms'), child: const Text('Read the Terms')),
                TextButton(onPressed: () => openLink('/privacy'), child: const Text('Privacy Policy')),
              ]),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_error!, key: const Key('su-error'), style: const TextStyle(color: StallColors.red, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('su-submit'),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: StallColors.onBrand))
                    : const Text('Create account'),
              ),
              const SizedBox(height: 10),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Already have an account? Sign in')),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Right after sign-up: confirm the email address (for order updates and password resets).
class FinishSetupScreen extends StatelessWidget {
  const FinishSetupScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final u = SessionScope.of(context).user;
    return Scaffold(
      appBar: AppBar(actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later'))]),
      body: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), children: [
        Text('Confirm your email', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 16),
        EmailCodeFlow(
          initialEmail: u?.email ?? '',
          autoSend: true,
          onDone: (r) {
            toast(context, 'Email confirmed ✓');
            Navigator.pop(context);
          },
        ),
      ]),
    );
  }
}

/// Send a 6-digit code to an email address, then confirm it. Used after sign-up, for school-email verification and email updates.
class EmailCodeFlow extends StatefulWidget {
  const EmailCodeFlow({super.key, this.initialEmail = '', this.autoSend = false, required this.onDone, this.hint = 'you@gmail.com'});
  final String initialEmail;
  final bool autoSend;
  final String hint;
  final void Function(Map<String, dynamic> result) onDone;
  @override
  State<EmailCodeFlow> createState() => _EmailCodeFlowState();
}

class _EmailCodeFlowState extends State<EmailCodeFlow> {
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  String? _sentTo, _err;
  bool _school = false, _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoSend && widget.initialEmail.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _send());
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(Api api) f) async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await f(SessionScope.of(context).api);
    } on ApiError catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() => _run((api) async {
        final em = _email.text.trim();
        if (!emailRule.hasMatch(em)) throw ApiError('Enter a valid email address.');
        final r = await api.post('verify/email/start', {'email': em});
        setState(() {
          _sentTo = em;
          _school = r['school'] != null && r['school'] != false;
        });
      });

  Future<void> _confirm() => _run((api) async {
        final r = await api.post('verify/email/confirm', {'code': _code.text.trim()});
        if (!mounted) return;
        await SessionScope.of(context).refresh();
        widget.onDone(r);
      });

  @override
  Widget build(BuildContext context) {
    final err = _err == null ? null : Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, key: const Key('em-error'), style: const TextStyle(color: StallColors.red)));
    final busy = _busy ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: StallColors.onBrand)) : null;
    if (_sentTo == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          key: const Key('em-email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: 'Email address', hintText: widget.hint),
        ),
        ?err,
        const SizedBox(height: 12),
        FilledButton(key: const Key('em-send'), onPressed: _busy ? null : _send, child: busy ?? const Text('Send code')),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text.rich(TextSpan(children: [
        const TextSpan(text: 'We sent a 6-digit code to '),
        TextSpan(text: _sentTo, style: const TextStyle(fontWeight: FontWeight.w700)),
        const TextSpan(text: '. Check your inbox and spam folder.'),
        if (!_school)
          const TextSpan(text: '\nThis isn\'t a school address, so it won\'t count as student verification, but you\'ll still get order updates.'),
      ])),
      const SizedBox(height: 12),
      TextField(
        key: const Key('em-code'),
        controller: _code,
        keyboardType: TextInputType.number,
        maxLength: 6,
        autofillHints: const [AutofillHints.oneTimeCode],
        decoration: const InputDecoration(labelText: 'Code', counterText: ''),
      ),
      ?err,
      const SizedBox(height: 12),
      FilledButton(key: const Key('em-confirm'), onPressed: _busy ? null : _confirm, child: busy ?? const Text('Confirm')),
      TextButton(onPressed: () => setState(() => _sentTo = null), child: const Text('Use a different email')),
    ]);
  }
}

/// Forgot password: email a code to the confirmed address, then set a new password with it.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialId = ''});
  final String initialId;
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _id = TextEditingController(text: widget.initialId);
  final _code = TextEditingController(), _pw = TextEditingController();
  String? _message, _err;
  bool _busy = false;

  @override
  void dispose() {
    _id.dispose();
    _code.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _go(Future<void> Function(Api api) f) async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await f(SessionScope.of(context).api);
    } on ApiError catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sent = _message != null;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), children: [
        Text(sent ? 'Check your email' : 'Reset your password', style: t.displaySmall),
        const SizedBox(height: 8),
        Text(sent ? _message! : 'We\'ll email a code to the address you confirmed on your account.',
            style: t.bodyLarge?.copyWith(color: StallColors.muted)),
        const SizedBox(height: 20),
        if (!sent)
          TextField(
              key: const Key('fg-id'),
              controller: _id,
              textCapitalization: TextCapitalization.characters,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number', hintText: '0803 123 4567'))
        else ...[
          TextField(
            key: const Key('fg-code'),
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: const InputDecoration(labelText: 'Code', counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('fg-pw'),
            controller: _pw,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(labelText: 'New password', hintText: 'At least 8 characters'),
          ),
        ],
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: const TextStyle(color: StallColors.red))),
        const SizedBox(height: 18),
        FilledButton(
          key: const Key('fg-go'),
          onPressed: _busy
              ? null
              : () => _go((api) async {
                    if (!sent) {
                      if (_id.text.trim().isEmpty) throw ApiError('Enter your phone number.');
                      final r = await api.post('auth/forgot', {'id': _id.text.trim()});
                      setState(() => _message = (r['message'] ?? 'If that account has a confirmed email, we have sent it a code.').toString());
                    } else {
                      if (_pw.text.length < 8) throw ApiError('Use at least 8 characters.');
                      await api.post('auth/reset', {'id': _id.text.trim(), 'code': _code.text.trim(), 'password': _pw.text});
                      if (!context.mounted) return;
                      toast(context, 'Password changed. Sign in with your new password');
                      Navigator.pop(context);
                    }
                  }),
          child: Text(sent ? 'Set new password' : 'Email me a code'),
        ),
        const SizedBox(height: 16),
        Text('No email on your account? Contact Stall support from your registered phone number and we\'ll help.', style: t.bodySmall),
      ]),
    );
  }
}

/// Turns a picked photo into the data URL the API takes (JPEG, small enough for the server's limit).
Future<String?> pickPhoto(BuildContext context, {ImagePicker? picker}) async {
  final src = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    backgroundColor: StallColors.cream,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
      ]),
    ),
  );
  if (src == null) return null;
  final p = picker ?? ImagePicker();
  for (final (w, q) in const [(1400.0, 75), (1000.0, 60), (800.0, 50)]) {
    final f = await p.pickImage(source: src, maxWidth: w, maxHeight: w, imageQuality: q);
    if (f == null) return null;
    final url = 'data:image/jpeg;base64,${base64Encode(await f.readAsBytes())}';
    if (url.length <= 440000) return url;
    // Too big for the server: try again smaller (the picker re-reads the same photo).
    if (src == ImageSource.camera) break;
  }
  throw ApiError('That photo is too large. Try another, or take it again a little further away.');
}

/// Verify you're a student: a school document (checked automatically, then by a person if unsure), or a school email address.
class VerifyStudentScreen extends StatefulWidget {
  const VerifyStudentScreen({super.key});
  @override
  State<VerifyStudentScreen> createState() => _VerifyStudentScreenState();
}

class _VerifyStudentScreenState extends State<VerifyStudentScreen> {
  static const _kinds = {
    'id': 'Student ID card',
    'courseform': 'Course registration form',
    'fees': 'School fees receipt',
    'admission': 'Admission letter',
  };
  String _kind = 'id';
  String? _photo, _err;
  bool _busy = false;

  Future<void> _pick() async {
    try {
      final p = await pickPhoto(context);
      if (p != null) setState(() => _photo = p);
    } on ApiError catch (e) {
      setState(() => _err = e.message);
    }
  }

  Future<void> _send() async {
    if (_photo == null) return setState(() => _err = 'Add a clear photo of your school document.');
    setState(() {
      _busy = true;
      _err = null;
    });
    final s = SessionScope.of(context);
    try {
      final r = await s.api.post('verify/id', {'kind': _kind, 'photo': _photo});
      await s.refresh();
      if (!mounted) return;
      toast(context, r['status'] == 'approved' ? 'Checked ✓ You\'re a verified student' : 'Sent. We\'ll check it soon');
      setState(() => _photo = null);
      // Opened from the "verify first" screen: go back so the app (or "we're checking") shows.
      if (Navigator.of(context).canPop() && (s.user?.vlevel ?? 0) < 1 && s.user?.verifyGate == true) Navigator.of(context).pop();
    } on ApiError catch (e) {
      setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final u = s.user;
    final t = Theme.of(context).textTheme;
    final lv = u?.vlevel ?? 0;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), children: [
        Text('Verify you\'re a student', style: t.displaySmall),
        const SizedBox(height: 8),
        Text(
          'Verified students get a badge on their listings and store, so buyers trust them more.'
          '${(u?.mustVerify ?? false) && lv < 1 ? ' You need to be verified to sell.' : ''}',
          style: t.bodyLarge?.copyWith(color: StallColors.muted),
        ),
        const SizedBox(height: 20),
        _Step(
          done: lv >= 2,
          title: 'Show a school document',
          tag: 'Works for everyone',
          child: lv >= 2
              ? const Text('Done. You have the Verified student badge.')
              : u?.idCheck == 'pending'
                  ? const Text('Thanks. The Stall team is checking it, usually within a day.', key: Key('vf-pending'))
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (u?.idCheck == 'rejected')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('Last one wasn\'t accepted: ${u!.idReason}. You can try again.', style: const TextStyle(color: StallColors.red)),
                        ),
                      const Text('Any one of these, with your name on it. We check it automatically, and a person looks if we\'re not sure. Only the Stall team ever sees it.'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
            isExpanded: true,
                        key: const Key('vf-kind'),
                        initialValue: _kind,
                        decoration: const InputDecoration(labelText: 'Document'),
                        items: [for (final e in _kinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                        onChanged: (v) => setState(() => _kind = v ?? 'id'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const Key('vf-photo'),
                        onPressed: _busy ? null : _pick,
                        icon: Icon(_photo == null ? Icons.add_a_photo_outlined : Icons.check_circle_rounded,
                            color: _photo == null ? null : StallColors.green),
                        label: Text(_photo == null ? 'Add a photo' : 'Photo added · change'),
                      ),
                      if (_photo != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.memory(base64Decode(_photo!.split(',').last), height: 160, fit: BoxFit.cover),
                          ),
                        ),
                      if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: const TextStyle(color: StallColors.red))),
                      const SizedBox(height: 12),
                      FilledButton(
                        key: const Key('vf-send'),
                        onPressed: _busy ? null : _send,
                        child: _busy ? const Text('Checking…') : const Text('Send for checking'),
                      ),
                    ]),
        ),
        if (lv < 1) ...[
          const SizedBox(height: 16),
          _Step(
            done: false,
            title: 'Or: a school email address',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Only if your school gave you an address ending in .edu.ng (or another domain the Stall team has added for your school). '
                  'A normal Gmail or Yahoo address can\'t prove you\'re a student, so use a document above instead.'),
              const SizedBox(height: 12),
              EmailCodeFlow(
                initialEmail: (u?.email ?? '').endsWith('.edu.ng') ? u!.email : '',
                hint: 'you@school.edu.ng',
                onDone: (r) {
                  final ok = ((r['vlevel'] as num?) ?? 0) >= 1;
                  toast(context,
                      ok ? 'School email confirmed ✓' : 'Email confirmed. It isn\'t a school address, so it doesn\'t verify you, but you\'ll get order updates there.');
                },
              ),
            ]),
          ),
        ],
        if (lv == 1) Padding(padding: const EdgeInsets.only(top: 12), child: Text('You have the School email badge. Show a document to get Verified student.', style: t.bodySmall)),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.done, required this.title, this.tag, required this.child});
  final bool done;
  final String title;
  final String? tag;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (done) const Icon(Icons.check_circle_rounded, color: StallColors.green, size: 20),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (tag != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: StallColors.cream2, borderRadius: BorderRadius.circular(99)),
                  child: Text(tag!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ]),
            const SizedBox(height: 10),
            child,
          ]),
        ),
      );
}

/// The badge text for someone's verification level (shown on Account).
String verifyLabel(StallUser u) =>
    u.vlevel >= 2 ? 'Verified student' : (u.vlevel == 1 ? 'School email confirmed' : (u.idCheck == 'pending' ? 'Being checked' : 'Not verified yet'));

/// Confirm or change the email used for order updates and password reset codes.
class EmailScreen extends StatefulWidget {
  const EmailScreen({super.key});
  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> {
  bool _change = false;
  @override
  Widget build(BuildContext context) {
    final u = SessionScope.of(context).user;
    final t = Theme.of(context).textTheme;
    final confirmed = (u?.emailVerified ?? false) && !_change;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), children: [
        Text('Email', style: t.displaySmall),
        const SizedBox(height: 8),
        Text('Get an email when someone buys from you, when your order is on the way, when you\'re paid or refunded, and codes to reset your password.',
            style: t.bodyLarge?.copyWith(color: StallColors.muted)),
        const SizedBox(height: 20),
        if (confirmed) ...[
          Text.rich(TextSpan(children: [const TextSpan(text: 'Sending to '), TextSpan(text: '${u!.email} ✓', style: const TextStyle(fontWeight: FontWeight.w700))])),
          TextButton(onPressed: () => setState(() => _change = true), child: const Text('Use a different email')),
        ] else
          EmailCodeFlow(
            initialEmail: _change ? '' : (u?.email ?? ''),
            onDone: (_) {
              toast(context, 'Email confirmed ✓');
              setState(() => _change = false);
            },
          ),
      ]),
    );
  }
}

/// Shown instead of the app while a student still needs to verify (when Admin requires it), like the web app's gate.
class VerifyGateScreen extends StatefulWidget {
  const VerifyGateScreen({super.key});
  @override
  State<VerifyGateScreen> createState() => _VerifyGateScreenState();
}

class _VerifyGateScreenState extends State<VerifyGateScreen> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final u = s.user!;
    final t = Theme.of(context).textTheme;
    final pend = u.idCheck == 'pending', rej = u.idCheck == 'rejected';
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 28, 24, 24), children: [
          const Align(alignment: Alignment.centerLeft, child: Wordmark(height: 30)),
          const SizedBox(height: 32),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: StallColors.lime, borderRadius: BorderRadius.circular(99)),
              child: Text(pend ? 'CHECKING' : 'ONE LAST STEP',
                  style: TextStyle(color: StallColors.indigo, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.3)),
            ),
          ),
          const SizedBox(height: 12),
          Text(pend ? 'We\'re checking your student ID' : 'Verify you\'re a student', style: t.displaySmall),
          const SizedBox(height: 10),
          Text(
            pend
                ? 'Thanks, ${u.firstName}. A person on the Stall team is looking at your document. This usually takes a few hours. We\'ll email you as soon as it\'s approved.'
                : rej
                    ? 'Your last document wasn\'t accepted: ${u.idReason.isEmpty ? 'it wasn\'t clear enough' : u.idReason}. Send a clearer photo, or a different school document.'
                    : 'Stall is only for students, so everyone shows a school document before they can buy, sell or chat. Most are checked in under a minute.',
            style: t.bodyLarge,
          ),
          const SizedBox(height: 24),
          if (pend)
            FilledButton(
              key: const Key('checkAgain'),
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      await s.refresh();
                      if (mounted) setState(() => _busy = false);
                    },
              child: Text(_busy ? 'Checking…' : 'Check again'),
            )
          else
            FilledButton(
              key: const Key('verifyNow'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VerifyStudentScreen())),
              child: const Text('Verify now'),
            ),
          const SizedBox(height: 16),
          Text('Accepted: student ID card, course registration form, school fees receipt or admission letter, with your name on it. Only the Stall team sees it.',
              style: t.bodySmall),
          const SizedBox(height: 12),
          TextButton(onPressed: s.signOut, child: const Text('Sign out')),
        ]),
      ),
    );
  }
}
