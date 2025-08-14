import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// SAME base URL you used elsewhere:
// Android emulator: http://10.0.2.2:8000
// iOS simulator:    http://localhost:8000
const String kBaseUrl = "http://10.0.2.2:8000";

const String kSignupPath = "/user/signup";
const String kSigninPath = "/user/login";   // <- matches your backend

const _kAccessToken = "access_token";
const _kIdToken = "id_token";
const _kRefreshToken = "refresh_token";
const _kExpiresAt = "expires_at_epoch_ms";

class AuthService {
  static Exception _extractError(http.Response res) {
    try {
      final m = jsonDecode(res.body);
      final detail = (m is Map && m["detail"] != null) ? m["detail"].toString() : null;
      return Exception(detail ?? "HTTP ${res.statusCode}");
    } catch (_) {
      return Exception("HTTP ${res.statusCode}");
    }
  }

  static Future<void> _saveTokens(Map<String, dynamic> tokenJson) async {
    final prefs = await SharedPreferences.getInstance();
    final access = tokenJson[_kAccessToken] as String?;
    final id = tokenJson[_kIdToken] as String?;
    final refresh = tokenJson[_kRefreshToken] as String?;
    final expiresIn = tokenJson["expires_in"] as int?;
    if (access == null || id == null || expiresIn == null) {
      throw Exception("Invalid token payload from server.");
    }
    final expiresAt = DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch;
    await prefs.setString(_kAccessToken, access);
    await prefs.setString(_kIdToken, id);
    if (refresh != null) await prefs.setString(_kRefreshToken, refresh);
    await prefs.setInt(_kExpiresAt, expiresAt);
  }

  static Future<void> signup({required String email, required String password, String? fullName}) async {
    final res = await http.post(
      Uri.parse("$kBaseUrl$kSignupPath"),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "email": email,
        "password": password,
        if (fullName != null && fullName.trim().isNotEmpty) "full_name": fullName.trim(),
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) throw _extractError(res);
    // if backend also returns tokens on signup, this will save them:
    try {
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic> && data.containsKey(_kAccessToken)) {
        await _saveTokens(data);
      }
    } catch (_) {}
  }

  static Future<void> signin({required String email, required String password}) async {
    final res = await http.post(
      Uri.parse("$kBaseUrl$kSigninPath"),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({"email": email, "password": password}),
    );
    if (res.statusCode == 200) {
      await _saveTokens(jsonDecode(res.body) as Map<String, dynamic>);
    } else {
      throw _extractError(res);
    }
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final access = prefs.getString(_kAccessToken);
    final exp = prefs.getInt(_kExpiresAt);
    if (access == null || exp == null) return false;
    return DateTime.now().millisecondsSinceEpoch < exp;
  }

  static Future<Map<String, String>> authHeaders({bool useIdToken = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = useIdToken ? prefs.getString(_kIdToken) : prefs.getString(_kAccessToken);
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kIdToken);
    await prefs.remove(_kRefreshToken);
    await prefs.remove(_kExpiresAt);
  }
}
