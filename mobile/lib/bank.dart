import 'package:flutter/material.dart';

import 'api.dart';
import 'main.dart';
import 'theme.dart';

/// The banks Stall can pay out to (GET /api/banks).
Future<List<(String, String)>> loadBanks(Api api) async {
  final r = await api.get('banks');
  return [for (final b in (r['banks'] as List? ?? const [])) ((b as Map)['code'].toString(), b['name'].toString())];
}

/// A payout account the person entered: checked with Paystack, or (if Paystack couldn't check it) with the name they typed.
class BankChoice {
  const BankChoice({required this.code, required this.acct, required this.name, required this.manual});
  final String code, acct, name;

  /// Paystack couldn't confirm the name: the Stall team checks it before the first payout.
  final bool manual;
}

/// Bank, account number and "Verify account". [onChanged] gets a [BankChoice] once the account is checked
/// (or a name is typed after Paystack couldn't check it), and null while it isn't ready.
class BankBox extends StatefulWidget {
  const BankBox({super.key, required this.onChanged, this.keyPrefix = 's', this.error});
  final ValueChanged<BankChoice?> onChanged;
  final String keyPrefix;

  /// A message from the form around it, e.g. "Tap Verify account first".
  final String? error;
  @override
  State<BankBox> createState() => _BankBoxState();
}

class _BankBoxState extends State<BankBox> {
  final _acct = TextEditingController(), _name = TextEditingController();
  List<(String, String)> _banks = const [];
  String? _bank, _verified, _msg;
  bool _checking = false, _manual = false;
  int _fails = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_banks.isEmpty) loadBanks(SessionScope.of(context).api).then((b) => mounted ? setState(() => _banks = b) : null).catchError((_) {});
  }

  @override
  void dispose() {
    _acct.dispose();
    _name.dispose();
    super.dispose();
  }

  String get _digits => _acct.text.replaceAll(RegExp(r'\D'), '');

  void _emit() {
    final name = _verified ?? (_manual ? _name.text.trim() : '');
    widget.onChanged(_bank != null && _digits.length == 10 && name.length >= 3
        ? BankChoice(code: _bank!, acct: _digits, name: name, manual: _verified == null)
        : null);
  }

  void _reset() {
    _verified = null;
    _fails = 0;
  }

  Future<void> _verify() async {
    if (_bank == null || _digits.length != 10) return setState(() => _msg = 'Choose your bank and enter your 10-digit account number.');
    setState(() {
      _checking = true;
      _msg = null;
    });
    try {
      final r = await SessionScope.of(context).api.post('bank/resolve', {'bank_code': _bank, 'acct_no': _digits});
      setState(() => _verified = r['name'].toString());
    } on ApiError catch (e) {
      setState(() {
        _fails++;
        _msg = e.message;
        // Paystack can't always check an account (busy, or not set up). After that, accept the name typed in.
        if (_fails >= 2 || e.status == 503 || e.message.contains('Type the name')) _manual = true;
      });
    } finally {
      if (mounted) setState(() => _checking = false);
      _emit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.keyPrefix;
    final err = _msg ?? widget.error;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<String>(
        key: Key('$p-bank'),
        isExpanded: true,
        initialValue: _bank,
        decoration: const InputDecoration(labelText: 'Bank'),
        items: [for (final b in _banks) DropdownMenuItem(value: b.$1, child: Text(b.$2))],
        onChanged: (v) {
          setState(() {
            _bank = v;
            _reset();
          });
          _emit();
        },
      ),
      const SizedBox(height: 12),
      TextField(
        key: Key('$p-acct'),
        controller: _acct,
        keyboardType: TextInputType.number,
        maxLength: 10,
        onChanged: (_) {
          setState(_reset);
          _emit();
        },
        decoration: const InputDecoration(labelText: 'Account number', hintText: '10 digits', counterText: ''),
      ),
      const SizedBox(height: 8),
      Row(children: [
        OutlinedButton(
            key: const Key('verifyBank'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _checking ? null : _verify,
            child: Text(_checking ? 'Checking…' : 'Verify account')),
        const SizedBox(width: 12),
        if (_verified != null)
          Expanded(child: Text('✓ $_verified', key: const Key('bankName'), style: const TextStyle(color: StallColors.green, fontWeight: FontWeight.w700))),
      ]),
      if (err != null && _verified == null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(err, style: const TextStyle(color: StallColors.red))),
      if (_manual && _verified == null) ...[
        const SizedBox(height: 10),
        TextField(
          key: Key('$p-acctName'),
          controller: _name,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => _emit(),
          decoration: const InputDecoration(labelText: 'Name on the account', hintText: 'Exactly as your bank shows it'),
        ),
        Text('The Stall team checks this name before your first payout.', style: Theme.of(context).textTheme.bodySmall),
      ],
    ]);
  }
}
