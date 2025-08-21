// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import '../services/auth_api.dart';
import '../widgets/auth_shell.dart';
import '../widgets/brand_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onAuthenticated});
  final VoidCallback? onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('User not confirmed')) {
      return 'Please confirm your email. Go to “Confirm” and use Resend if needed.';
    }
    if (s.contains('Incorrect username or password')) {
      return 'Email or password is incorrect.';
    }
    if (s.contains("Can't reach the server")) {
      return "Can't reach the server. Make sure the backend is running and CORS allows this origin.";
    }
    return 'Could not sign in: $s';
    }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthApi.login(
        email: _email.text.trim(),
        password: _password.text,
      );
      widget.onAuthenticated?.call();
      if (!mounted) return;
      // Clear stack and go to map (or your post-login home)
      Navigator.of(context).pushNamedAndRemoveUntil('/map', (r) => false);
    } catch (e) {
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthShell(
        title: 'Welcome back',
        subtitle: 'Sign in to continue to SafeSteps',
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
                textInputAction: TextInputAction.next,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter your email';
                  if (!v.contains('@')) return 'Enter a valid email';
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
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  ),
                ),
                obscureText: _obscure,
                onFieldSubmitted: (_) => _busy ? null : _submit(),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter your password';
                  if (v.length < 8) return 'At least 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 14),
              BrandButton(
                label: _busy ? 'Signing in…' : 'Sign In',
                icon: Icons.login,
                busy: _busy,
                onPressed: _busy ? null : _submit,
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).pushNamed('/signup'),
                child: const Text("Don't have an account? Create one"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
