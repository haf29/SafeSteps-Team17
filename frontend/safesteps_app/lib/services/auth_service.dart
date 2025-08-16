// lib/services/auth_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthApi {
  // TODO: point this at your machine / deployed API
  // Example: const String baseUrl = "http://127.0.0.1:8000";
  static const String baseUrl = "http://127.0.0.1:8000";

  static Future<void> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse("$baseUrl/user/signup");
    final res = await http.post(
      uri,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "full_name": fullName,
        "email": email,
        "password": password,
      }),
    );

    if (res.statusCode >= 400) {
      throw Exception(_extractError(res.body) ?? "Sign up failed");
    }
  }

  static Future<void> confirm({
    required String email,
    required String code,
  }) async {
    final uri = Uri.parse("$baseUrl/user/confirm");
    final res = await http.post(
      uri,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "email": email,
        "code": code,
      }),
    );

    if (res.statusCode >= 400) {
      throw Exception(_extractError(res.body) ?? "Confirmation failed");
    }
  }

  static Future<void> login({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse("$baseUrl/user/login");
    final res = await http.post(
      uri,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "email": email,
        "password": password,
      }),
    );

    if (res.statusCode >= 400) {
      final err = _extractError(res.body) ?? "Login failed";
      throw Exception(err);
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("access_token", data["access_token"] ?? "");
    await prefs.setString("id_token", data["id_token"] ?? "");
    await prefs.setString("refresh_token", data["refresh_token"] ?? "");
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("access_token");
    await prefs.remove("id_token");
    await prefs.remove("refresh_token");
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString("access_token") ?? "").isNotEmpty;
  }

  static String? _extractError(String body) {
    try {
      final obj = jsonDecode(body);
      if (obj is Map && obj["detail"] != null) {
        return obj["detail"].toString();
      }
    } catch (_) {}
    return null;
  }
}
