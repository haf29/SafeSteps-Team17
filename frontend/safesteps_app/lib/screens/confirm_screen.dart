// lib/screens/confirm_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_api.dart';
import '../widgets/auth_shell.dart';
import '../widgets/brand_button.dart';

class ConfirmScreen extends StatefulWidget {
  const ConfirmScreen({super.key});

  @override
  State<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends State<ConfirmScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();

  bool _busy = false;
  String? _error;
  String? _info;

  int _cooldown = 0;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is String && _email.text.isEmpty) {
      _email.text = arg;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown([int seconds = 30]) {
    setState(() => _cooldown = seconds);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  Future<void> _confirm() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; _info = null; });
    try {
      await AuthApi.confirm(email: _email.text.trim(), code: _code.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account confirmed. Please sign in.')),
      );
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _busy = false; });
    }
  }

  Future<void> _resend() async {
    setState(() { _busy = true; _error = null; _info = null; });
    try {
      await AuthApi.resendCode(email: _email.text.trim());
      setState(() { _info = 'A new code has been sent to your email.'; });
      _startCooldown();
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthShell(
        title: 'Confirm your email',
        subtitle: 'Enter the 6-digit code sent to your inbox',
        child: Form(
          key: _form,
          child: Column(
            children: [
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _code,
                decoration: const InputDecoration(
                  labelText: 'Confirmation code',
                  prefixIcon: Icon(Icons.verified_user_outlined),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Enter the code' : null,
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Align(alignment: Alignment.centerLeft, child: Text(_error!, style: const TextStyle(color: Colors.red))),
              if (_info != null)
                Align(alignment: Alignment.centerLeft, child: Text(_info!, style: const TextStyle(color: Colors.green))),
              const SizedBox(height: 14),
              BrandButton(
                label: _busy ? 'Confirming…' : 'Confirm',
                icon: Icons.check_circle_outline,
                busy: _busy,
                onPressed: _busy ? null : _confirm,
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _busy || _cooldown > 0 ? null : _resend,
                child: Text(_cooldown > 0 ? 'Resend code ($_cooldown)' : 'Resend code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
