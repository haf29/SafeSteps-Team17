// lib/services/auth_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthApi {
  // Use a --dart-define at run time or change the default:
  // flutter run -d chrome --dart-define=API_BASE=http://localhost:8000
  static const String _apiBase =
      String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8000');

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kId = 'id_token';
  static const _kExp = 'expires_in';

  // ---------- Session helpers ----------
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_kAccess);
    return t != null && t.isNotEmpty;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
    await prefs.remove(_kId);
    await prefs.remove(_kExp);
  }

  static Future<Map<String, String>> authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_kAccess);
    return {
      'Content-Type': 'application/json',
      if (t != null && t.isNotEmpty) 'Authorization': 'Bearer $t',
    };
  }

  // ---------- API calls ----------
  // POST /user/signup -> {message, user_sub}
  static Future<SignupResult> signup({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final res = await http.post(
      Uri.parse('$_apiBase/user/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'full_name': fullName,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Signup failed (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return SignupResult(
      message: data['message']?.toString() ?? 'Signed up',
      userSub: data['user_sub']?.toString(),
    );
  }

  // POST /user/confirm -> 204
  static Future<void> confirm({
    required String email,
    required String code,
  }) async {
    final res = await http.post(
      Uri.parse('$_apiBase/user/confirm'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code}),
    );
    if (res.statusCode != 204) {
      throw Exception('Confirmation failed (${res.statusCode}): ${res.body}');
    }
  }

  // POST /user/resend-code -> 204
  static Future<void> resendCode({required String email}) async {
    final res = await http.post(
      Uri.parse('$_apiBase/user/resend-code'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    if (res.statusCode != 204) {
      throw Exception('Resend code failed (${res.statusCode}): ${res.body}');
    }
  }

  // POST /user/login -> {access_token, refresh_token?, id_token, expires_in}
  static Future<void> login({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$_apiBase/user/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Login failed (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccess, (data['access_token'] ?? '').toString());
    await prefs.setString(_kId, (data['id_token'] ?? '').toString());
    if (data['refresh_token'] != null) {
      await prefs.setString(_kRefresh, data['refresh_token'].toString());
    }
    if (data['expires_in'] != null) {
      await prefs.setString(_kExp, data['expires_in'].toString());
    }
  }
}

class SignupResult {
  final String message;
  final String? userSub;
  SignupResult({required this.message, this.userSub});
}
