// lib/services/auth_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final String idToken;
  final int expiresIn;

  AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.idToken,
    required this.expiresIn,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> j) => AuthTokens(
        accessToken: j['access_token'] ?? '',
        refreshToken: j['refresh_token'] ?? '',
        idToken: j['id_token'] ?? '',
        expiresIn: j['expires_in'] ?? 0,
      );
}

class AuthApi {
  // Change this if your API runs elsewhere
  static const String _base = 'http://127.0.0.1:8000';

  Future<void> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final resp = await http.post(
      Uri.parse('$_base/user/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'full_name': fullName,
        'email': email,
        'password': password,
      }),
    );

    if (resp.statusCode != 201) {
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      throw Exception(body['detail'] ?? 'Signup failed (${resp.statusCode})');
    }
  }

  Future<void> confirm({
    required String email,
    required String code,
  }) async {
    final resp = await http.post(
      Uri.parse('$_base/user/confirm'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code}),
    );

    if (resp.statusCode != 200) {
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      throw Exception(body['detail'] ?? 'Confirmation failed (${resp.statusCode})');
    }
  }

  Future<AuthTokens> login({
    required String email,
    required String password,
  }) async {
    final resp = await http.post(
      Uri.parse('$_base/user/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (resp.statusCode != 200) {
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      throw Exception(body['detail'] ?? 'Login failed (${resp.statusCode})');
    }

    return AuthTokens.fromJson(jsonDecode(resp.body));
  }
}
