import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';

import '../models/hex_zone_model.dart';

class HiveService {
  static const String hexBoxName = "hex_zones";

  // ===== API base for dev =====
  // iOS simulator / Web / desktop localhost:
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://127.0.0.1:8000',
  );
  // Android emulator uses host via 10.0.2.2 — keep here for later:
  // static const String apiBase = 'http://10.0.2.2:8000';

  // Keys for 'meta' box
  static const String _kWarmupDone = 'warmup_done';
  static const String _kLastCityRefreshPrefix = 'last_city_refresh_';

  // -------- Init --------
  static Future<void> initHive() async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(HexZoneAdapter());
    }
    await Future.wait([
      Hive.openBox<HexZone>(hexBoxName),
      Hive.openBox('meta'),
    ]);
  }

  // Convenience (alias) so old code can call loadZones/saveZones
  static List<HexZone> loadZones() =>
      Hive.box<HexZone>(hexBoxName).values.toList();

  static Future<void> saveZones(List<HexZone> zones) async {
    final box = Hive.box<HexZone>(hexBoxName);
    await box.clear();
    for (final z in zones) {
      await box.put(z.zoneId, z);
    }
  }

  // -------- One-time warmup: /hex_zones_lebanon --------
  static Future<void> warmupAllLebanon() async {
    final meta = Hive.box('meta');
    final zonesBox = Hive.box<HexZone>(hexBoxName);

    if (meta.get(_kWarmupDone, defaultValue: false) == true) {
      return; // already warmed on this device
    }

    final res = await http.get(Uri.parse('$apiBase/hex_zones_lebanon'));
    if (res.statusCode != 200) {
      throw Exception('warmupAllLebanon failed: ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final zones = (data['zones'] as List).cast<Map<String, dynamic>>();

    for (final z in zones) {
      final id = z['zone_id'] as String;
      final colorHex = (z['color'] as String?) ?? '#00FF00';
      final colorValue = int.parse('0xFF${colorHex.replaceAll("#", "")}');
      final score = (z['score'] as num?)?.toDouble() ?? 0.0;
      final city = (z['city'] as String?) ?? '';

      final boundary = (z['boundary'] as List?)
              ?.map<List<double>>((p) =>
                  (p as List).map((x) => (x as num).toDouble()).toList())
              .toList() ??
          const <List<double>>[];

      final existing = zonesBox.get(id);
      if (existing == null) {
        zonesBox.put(
          id,
          HexZone(
            zoneId: id,
            boundary: boundary,
            colorValue: colorValue,
            score: score,
            city: city,
            updatedAt: DateTime.now(),
          ),
        );
      } else {
        existing.boundary =
            existing.boundary.isNotEmpty ? existing.boundary : boundary;
        existing.colorValue = colorValue;
        existing.score = score;
        if (city.isNotEmpty) existing.city = city;
        existing.updatedAt = DateTime.now();
        await existing.save();
      }
    }

    await meta.put(_kWarmupDone, true);
  }

  // -------- Targeted refresh: /hex_zones?lat=..&lng=.. --------
  static Future<void> refreshCityByLatLng(
    double lat,
    double lng, {
    Duration ttl = const Duration(minutes: 20),
  }) async {
    final meta = Hive.box('meta');
    final zonesBox = Hive.box<HexZone>(hexBoxName);

    final res = await http.get(Uri.parse('$apiBase/hex_zones?lat=$lat&lng=$lng'));
    if (res.statusCode != 200) {
      throw Exception('refreshCity failed: ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final city = (data['city'] as String?) ?? '';
    if (city.isEmpty) return;

    // TTL
    final key = '$_kLastCityRefreshPrefix$city';
    final lastIso = meta.get(key) as String?;
    if (lastIso != null) {
      final last = DateTime.tryParse(lastIso);
      if (last != null && DateTime.now().difference(last) < ttl) {
        return;
      }
    }

    final zones = (data['zones'] as List).cast<Map<String, dynamic>>();
    for (final z in zones) {
      final id = z['zone_id'] as String;
      final colorHex = (z['color'] as String?) ?? '#00FF00';
      final colorValue = int.parse('0xFF${colorHex.replaceAll("#", "")}');
      final score = (z['score'] as num?)?.toDouble() ?? 0.0;

      final boundary = (z['boundary'] as List?)
              ?.map<List<double>>((p) =>
                  (p as List).map((x) => (x as num).toDouble()).toList())
              .toList() ??
          const <List<double>>[];

      final existing = zonesBox.get(id);
      if (existing == null) {
        zonesBox.put(
          id,
          HexZone(
            zoneId: id,
            boundary: boundary,
            colorValue: colorValue,
            score: score,
            city: city,
            updatedAt: DateTime.now(),
          ),
        );
      } else {
        if (boundary.isNotEmpty) existing.boundary = boundary;
        existing.colorValue = colorValue;
        existing.score = score;
        if (city.isNotEmpty) existing.city = city;
        existing.updatedAt = DateTime.now();
        await existing.save();
      }
    }

    await meta.put(key, DateTime.now().toIso8601String());
  }
}
