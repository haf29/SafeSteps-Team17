import 'dart:convert';
import 'package:http/http.dart' as http;

abstract class AuthService {
  Future<void> signup({required String name, required String email, required String password});
  Future<String> login({required String email, required String password});
  Future<void> sendReset({required String email});
}

class RealAuthService implements AuthService {
  RealAuthService({String? base})
      : baseUrl = base ?? const String.fromEnvironment('API_BASE', defaultValue: 'http://127.0.0.1:8000');

  final String baseUrl;
  Duration get _timeout => const Duration(seconds: 12);

  @override
  Future<void> signup({required String name, required String email, required String password}) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/user/signup'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'full_name': name, 'email': email, 'password': password}),
        )
        .timeout(_timeout);

    if (res.statusCode >= 400) {
      throw Exception(_extractError(res.body, fallback: 'Sign up failed'));
    }
  }

  @override
  Future<String> login({required String email, required String password}) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/user/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_timeout);

    if (res.statusCode >= 400) {
      throw Exception(_extractError(res.body, fallback: 'Invalid email or password'));
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return (m['access_token'] as String?) ?? '';
  }

  @override
  Future<void> sendReset({required String email}) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/user/forgot'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(_timeout);

    if (res.statusCode >= 400) {
      throw Exception(_extractError(res.body, fallback: 'Could not send reset link'));
    }
  }

  String _extractError(String body, {required String fallback}) {
    try {
      final m = jsonDecode(body);
      if (m is Map && m['detail'] is String) return m['detail'];
    } catch (_) {}
    return fallback;
  }
}

class MockAuthService implements AuthService {
  Duration get _delay => const Duration(milliseconds: 600);

  @override
  Future<void> signup({required String name, required String email, required String password}) async {
    await Future.delayed(_delay);
    if (email.contains('exists')) throw Exception('Email already exists');
  }

  @override
  Future<String> login({required String email, required String password}) async {
    await Future.delayed(_delay);
    if (password.length < 8) throw Exception('Password must be at least 8 characters');
    return 'mock-token-123';
  }

  @override
  Future<void> sendReset({required String email}) async {
    await Future.delayed(_delay);
  }
}

AuthService makeAuthService() {
  const useMock = bool.fromEnvironment('USE_MOCK', defaultValue: false);
  return useMock ? MockAuthService() : RealAuthService();
}
