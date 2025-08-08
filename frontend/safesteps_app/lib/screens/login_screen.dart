import 'package:flutter/material.dart';
import 'map_screen.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  late final AuthService _auth;

  bool _isLoading = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _showForgotPassword = false;

  @override
  void initState() {
    super.initState();
    _auth = makeAuthService();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  // ---------- Password policy helpers ----------
  final _upper = RegExp(r'[A-Z]');
  final _lower = RegExp(r'[a-z]');
  final _digit = RegExp(r'\d');
  // IMPORTANT FIX: use triple-quoted raw string so both ' and " are allowed
  final _special = RegExp(
    r'''[!@#\$%\^&\*\(\)_\+\-\=\[\]\{\};':"\\|,.<>\/\?]'''
  );

  bool _isStrongPassword(String pw, String email) {
    if (pw.trim() != pw) return false;
    if (pw.length < 12) return false;
    if (!_upper.hasMatch(pw)) return false;
    if (!_lower.hasMatch(pw)) return false;
    if (!_digit.hasMatch(pw)) return false;
    if (!_special.hasMatch(pw)) return false;
    final local = email.split('@').first.toLowerCase();
    if (local.isNotEmpty && pw.toLowerCase().contains(local)) return false;
    if (pw.toLowerCase().contains('password')) return false;
    return true;
  }

  int _passwordScore(String pw) {
    int score = 0;
    if (pw.length >= 12) score++;
    if (_upper.hasMatch(pw)) score++;
    if (_lower.hasMatch(pw)) score++;
    if (_digit.hasMatch(pw)) score++;
    if (_special.hasMatch(pw)) score++;
    return score.clamp(0, 5);
  }

  Color _scoreColor(int score) {
    switch (score) {
      case 0:
      case 1:
        return Colors.red;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.amber;
      case 4:
        return Colors.lightGreen;
      default:
        return Colors.green;
    }
  }

  Future<void> _handleAuth() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      if (_isSignUp) {
        await _auth.signup(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (!mounted) return;
        _showSuccess('Account created successfully! Please sign in.');
        setState(() {
          _isSignUp = false;
          _emailController.clear();
          _passwordController.clear();
          _nameController.clear();
        });
      } else {
        final _ = await _auth.login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MapScreen()),
        );
      }
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('Please enter your email address first');
      return;
    }
    if (!_isValidEmail(email)) {
      _showError('Please enter a valid email address');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _auth.sendReset(email: email);
      _showSuccess('Password reset link sent to $email');
    } catch (_) {
      _showError('Failed to send reset link. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isValidEmail(String v) => RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v);

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red, duration: const Duration(seconds: 3)),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green, duration: const Duration(seconds: 3)),
    );
  }

  void _toggleAuthMode() {
    setState(() {
      _isSignUp = !_isSignUp;
      _emailController.clear();
      _passwordController.clear();
      _nameController.clear();
      _showForgotPassword = false;
    });
  }

  void _toggleForgotPassword() {
    setState(() => _showForgotPassword = !_showForgotPassword);
  }

  @override
  Widget build(BuildContext context) {
    final pwd = _passwordController.text;
    final score = _passwordScore(pwd);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shield, size: 64, color: Color(0xFF1E3A8A)),
                        const SizedBox(height: 16),
                        Text(
                          'SafeSteps',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E3A8A),
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isSignUp ? 'Create your account' : 'Sign in to continue',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 32),

                        if (_isSignUp) ...[
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Full Name',
                              prefixIcon: Icon(Icons.person),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (_isSignUp && (value == null || value.isEmpty)) {
                                return 'Please enter your name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                        ],

                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'Please enter your email';
                            if (!_isValidEmail(value)) return 'Please enter a valid email';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'Please enter your password';
                            if (_isSignUp) {
                              return _isStrongPassword(value, _emailController.text.trim())
                                  ? null
                                  : 'Password must be 12+ chars and include upper, lower, digit, special';
                            } else {
                              if (value.length < 8) return 'Password must be at least 8 characters';
                              return null;
                            }
                          },
                        ),

                        if (_isSignUp && pwd.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: score / 5.0,
                                  color: _scoreColor(score),
                                  backgroundColor: Colors.grey.shade300,
                                  minHeight: 6,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                ["Very weak","Weak","Okay","Good","Strong","Strong"][score],
                                style: TextStyle(color: _scoreColor(score)),
                              )
                            ],
                          ),
                          const SizedBox(height: 8),
                          _ruleRow("12+ characters", pwd.length >= 12),
                          _ruleRow("Uppercase (A-Z)", _upper.hasMatch(pwd)),
                          _ruleRow("Lowercase (a-z)", _lower.hasMatch(pwd)),
                          _ruleRow("Digit (0-9)", _digit.hasMatch(pwd)),
                          _ruleRow("Special (!@#…)", _special.hasMatch(pwd)),
                          const SizedBox(height: 8),
                        ],

                        const SizedBox(height: 16),

                        if (!_isSignUp) ...[
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _isLoading ? null : _toggleForgotPassword,
                              child: const Text('Forgot Password?', style: TextStyle(color: Color(0xFF1E3A8A))),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],

                        if (!_isSignUp && _showForgotPassword) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.email, color: Colors.blue[600], size: 20),
                                    const SizedBox(width: 8),
                                    Text('Reset Password', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[700])),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text('Enter your email to receive a password reset link.', style: TextStyle(color: Colors.blue[600], fontSize: 12)),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _handleForgotPassword,
                                    child: _isLoading
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                        : const Text('Send Reset Link', style: TextStyle(color: Colors.white)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleAuth,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E3A8A),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: _isLoading
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Text(_isSignUp ? 'Sign Up' : 'Sign In', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ),
                        const SizedBox(height: 16),

                        TextButton(
                          onPressed: _isLoading ? null : _toggleAuthMode,
                          child: Text(
                            _isSignUp ? 'Already have an account? Sign In' : 'Don\'t have an account? Sign Up',
                            style: const TextStyle(color: Color(0xFF1E3A8A)),
                          ),
                        ),

                        if (!_isSignUp && !_showForgotPassword) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: const Column(
                              children: [
                                Text('Test Credentials:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                                SizedBox(height: 4),
                                Text('Email: test@test.com\nPassword: password123AA!', style: TextStyle(color: Color(0xFF1E3A8A), fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ruleRow(String text, bool ok) {
    return Row(
      children: [
        Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16, color: ok ? Colors.green : Colors.grey),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: ok ? Colors.green : Colors.grey[700])),
      ],
    );
  }
}
