import 'package:flutter/material.dart';
import '../services/auth_api.dart';
import '../widgets/auth_shell.dart';
import '../widgets/brand_button.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _phone = TextEditingController();

  bool _busy = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _phone.dispose();
    super.dispose();
  }

  String? _validateStrongPassword(String? v, String email) {
    if (v == null || v.isEmpty) return 'Enter a password';
    if (v.length < 12) return 'At least 12 characters';
    final hasLower = RegExp(r'[a-z]').hasMatch(v);
    final hasUpper = RegExp(r'[A-Z]').hasMatch(v);
    final hasDigit = RegExp(r'\d').hasMatch(v);
    final hasSymbol = RegExp(r'[^A-Za-z0-9]').hasMatch(v);
    if (!(hasLower && hasUpper && hasDigit && hasSymbol)) {
      return 'Need lower, upper, number, and symbol';
    }
    final local = email.split('@').first.toLowerCase();
    if (local.isNotEmpty && v.toLowerCase().contains(local)) {
      return 'Must not contain your email name';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final phoneNumber = '+961${_phone.text.trim()}'; // ✅ Always E.164 format

      final res = await AuthApi.signup(
        email: _email.text.trim(),
        password: _password.text,
        fullName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        phone: phoneNumber,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(res.message)));
      Navigator.of(context)
          .pushNamed('/confirm', arguments: _email.text.trim());
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthShell(
        title: 'Create your account',
        subtitle: 'Join SafeSteps to report incidents and stay informed',
        child: Form(
          key: _form,
          child: Column(
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Full name (optional)',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) =>
                    (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  prefixText: '+961 ',
                  prefixIcon: Icon(Icons.phone),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter your phone number';
                  if (v.length < 7 || v.length > 8) {
                    return 'Enter a valid Lebanese phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure1 = !_obscure1),
                    icon: Icon(
                        _obscure1 ? Icons.visibility : Icons.visibility_off),
                  ),
                ),
                obscureText: _obscure1,
                validator: (v) => _validateStrongPassword(v, _email.text.trim()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirm,
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: const Icon(Icons.password),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure2 = !_obscure2),
                    icon: Icon(
                        _obscure2 ? Icons.visibility : Icons.visibility_off),
                  ),
                ),
                obscureText: _obscure2,
                validator: (v) =>
                    v != _password.text ? 'Passwords do not match' : null,
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              const SizedBox(height: 14),
              BrandButton(
                label: _busy ? 'Creating…' : 'Create account',
                icon: Icons.person_add_alt_1,
                busy: _busy,
                onPressed: _busy ? null : _submit,
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).pushNamed('/login'),
                child: const Text('Already have an account? Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}