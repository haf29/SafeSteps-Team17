// lib/services/auth_api.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthApi {
  /// Base like: http://127.0.0.1:8000  (no trailing slash needed)
  /// You can override from the CLI:
  ///   flutter run -d chrome --dart-define API_BASE_URL=http://127.0.0.1:8000
  static const String _apiBase = String.fromEnvironment(
    'API_BASE_URL',
    // keep your current default remote host; override via --dart-define for local
    defaultValue: 'http://51.20.9.164:8000',
  );

  /// Optional global prefix like "/api"
  /// Override from CLI:
  ///   --dart-define API_PREFIX=/api
  static const String _apiPrefix = String.fromEnvironment('API_PREFIX', defaultValue: '');

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kId = 'id_token';
  static const _kExp = 'expires_in';

  // ---------------- URL builder ----------------
  static Uri _uri(String path) {
    // Normalize base
    final base = Uri.parse(_apiBase);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;

    // Normalize prefix
    String pfx = _apiPrefix.trim();
    if (pfx.isNotEmpty && !pfx.startsWith('/')) pfx = '/$pfx';
    if (pfx.endsWith('/')) pfx = pfx.substring(0, pfx.length - 1);

    // Normalize leaf path
    final leaf = path.startsWith('/') ? path : '/$path';

    final fullPath = '$basePath$pfx$leaf';
    return base.replace(path: fullPath);
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
  static Future<http.Response> _post(
    String path,
    Map<String, dynamic> body, {
    bool auth = false,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final url = _uri(path);
    try {
      final headers = auth ? await authHeaders() : {'Content-Type': 'application/json'};
      final res = await http.post(url, headers: headers, body: jsonEncode(body)).timeout(timeout);
      return res;
    } on TimeoutException {
      throw Exception(
        "Request to $url timed out. Ensure the backend is running and reachable.",
      );
    } catch (e) {
      throw Exception(
        "Can't reach the server at $_apiBase (resolved URL: $url). "
        "Check that FastAPI is running and CORS allows your Flutter web origin.\n$e",
      );
    }
  }

  // --------------- Calls ---------------
  static Future<SignupResult> signup({
    required String email,
    required String password,
    String? fullName,
    required String phone, // kept
  }) async {
    final res = await _post('/user/signup', {
      'email': email,
      'password': password,
      'full_name': fullName,
      'phone': phone,
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

  static Future<void> confirm({required String email, required String code}) async {
    final res = await _post('/user/confirm', {'email': email, 'code': code});
    _log('confirm → ${res.statusCode}: ${res.body}');
    if (res.statusCode != 204) throw _extractError('Confirmation failed', res);
  }

  static Future<void> resendCode({required String email}) async {
    final res = await _post('/user/resend-code', {'email': email});
    _log('resend → ${res.statusCode}: ${res.body}');
    if (res.statusCode != 204) throw _extractError('Resend code failed', res);
  }

  static Future<void> login({required String email, required String password}) async {
    final res = await _post('/user/login', {'email': email, 'password': password});
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
