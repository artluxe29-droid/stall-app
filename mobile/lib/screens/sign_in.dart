import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account_setup.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false, _hide = true;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SessionScope.of(context).signIn(_phone.text, _pw.text);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final brk = SessionScope.of(context).breakMessage;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Align(alignment: Alignment.centerLeft, child: Wordmark(height: 34)),
              const SizedBox(height: 36),
              if (brk != null) ...[BreakCard(message: brk), const SizedBox(height: 24)],
              Text('Welcome back', style: t.displaySmall),
              const SizedBox(height: 8),
              Text('Sign in to buy and sell safely with students and campus vendors.',
                  style: t.bodyLarge?.copyWith(color: StallColors.muted)),
              const SizedBox(height: 28),
              TextFormField(
                key: const Key('phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Phone or matric number', hintText: '0803 123 4567'),
                validator: (v) => (v ?? '').trim().length < 4 ? 'Enter your phone or matric number.' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('password'),
                controller: _pw,
                obscureText: _hide,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    tooltip: _hide ? 'Show password' : 'Hide password',
                    icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ),
                validator: (v) => (v ?? '').isEmpty ? 'Enter your password.' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, key: const Key('error'), style: const TextStyle(color: StallColors.red, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 22),
              FilledButton(
                key: const Key('signIn'),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Sign in'),
              ),
              const SizedBox(height: 18),
              TextButton(
                key: const Key('forgot'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ForgotPasswordScreen(initialId: _phone.text.trim()))),
                child: const Text('Forgot your password?'),
              ),
              const SizedBox(height: 4),
              OutlinedButton(
                key: const Key('toSignUp'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignUpScreen())),
                child: const Text('New here? Create an account'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
