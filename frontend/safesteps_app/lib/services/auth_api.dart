import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthApi {
  static const String _apiBase =
      String.fromEnvironment('API_BASE', defaultValue: 'http://51.20.9.164:8000');

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kId = 'id_token';
  static const _kExp = 'expires_in';

  static Uri _url(String path) {
    final base = Uri.parse(_apiBase);
    final p = (base.path.endsWith('/')
            ? base.path.substring(0, base.path.length - 1)
            : base.path) +
        path;
    return base.replace(path: p);
  }

  static void _log(String msg) {
    if (kDebugMode) debugPrint(msg);
  }

  // ---------------- Session ----------------
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

  // --------------- HTTP helpers ---------------
  static Future<http.Response> _post(String path, Map<String, dynamic> body,
      {bool auth = false}) async {
    try {
      final headers =
          auth ? await authHeaders() : {'Content-Type': 'application/json'};
      final res =
          await http.post(_url(path), headers: headers, body: jsonEncode(body));
      return res;
    } catch (_) {
      throw Exception(
        "Can't reach the server at $_apiBase. "
        "Check that FastAPI is running and CORS allows your Flutter web origin.",
      );
    }
  }

  // --------------- Calls ---------------
  static Future<SignupResult> signup({
    required String email,
    required String password,
    String? fullName,
    required String phone, // ✅ new param
  }) async {
    final res = await _post('/user/signup', {
      'email': email,
      'password': password,
      'full_name': fullName,
      'phone': phone, // ✅ added to request
    });
    _log('signup → ${res.statusCode}: ${res.body}');
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _extractError('Signup failed', res);
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return SignupResult(
      message: data['message']?.toString() ?? 'Signed up',
      userSub: data['user_sub']?.toString(),
    );
  }

  static Future<void> confirm(
      {required String email, required String code}) async {
    final res = await _post('/user/confirm', {'email': email, 'code': code});
    _log('confirm → ${res.statusCode}: ${res.body}');
    if (res.statusCode != 204) throw _extractError('Confirmation failed', res);
  }

  static Future<void> resendCode({required String email}) async {
    final res = await _post('/user/resend-code', {'email': email});
    _log('resend → ${res.statusCode}: ${res.body}');
    if (res.statusCode != 204) throw _extractError('Resend code failed', res);
  }

  static Future<void> login(
      {required String email, required String password}) async {
    final res =
        await _post('/user/login', {'email': email, 'password': password});
    _log('login → ${res.statusCode}: ${res.body}');
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _extractError('Login failed', res);
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

  static Exception _extractError(String label, http.Response res) {
    String msg = res.body;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['detail'] != null) {
        msg = decoded['detail'].toString();
      }
    } catch (_) {}
    return Exception('$label (${res.statusCode}): $msg');
  }
}

class SignupResult {
  final String message;
  final String? userSub;
  SignupResult({required this.message, this.userSub});
}