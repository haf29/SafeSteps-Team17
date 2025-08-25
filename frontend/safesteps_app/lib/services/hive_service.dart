import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';

import '../models/hex_zone_model.dart';

class HiveService {
  static const String hexBoxName = "hex_zones";

  // ===== API base for dev =====
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://51.20.9.164:8000',
  );
  // static const String apiBase = 'http://10.0.2.2:8000'; // Android emulator

  // Keys for 'meta' box
  static const String _kWarmupDone = 'warmup_done';
  static const String _kLastCityRefreshPrefix = 'last_city_refresh_';

  // ---------- Init ----------
  static Future<void> initHive() async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(HexZoneAdapter());
    }
    await Future.wait([
      Hive.openBox<HexZone>(hexBoxName),
      Hive.openBox('meta'),
    ]);
  }

  static bool get isWarmupDone =>
      Hive.box('meta').get(_kWarmupDone, defaultValue: false) == true;

  // ---------- Load / Save ----------
  static List<HexZone> loadZones() =>
      Hive.box<HexZone>(hexBoxName).values.toList();

  /// Upsert a batch efficiently (no clear, no many small writes)
  static Future<void> saveZonesBatch(List<HexZone> zones) async {
    final box = Hive.box<HexZone>(hexBoxName);
    final map = <String, HexZone>{
      for (final z in zones) z.zoneId: z,
    };
    await box.putAll(map);
  }
  // Heuristic: are points probably swapped (lng,lat) instead of (lat,lng)?
static bool _looksSwappedForLebanon(List<List<double>> pts) {
  if (pts.isEmpty) return false;

  // Lebanon rough bounding box:
  // lat: 33.0–34.9, lng: 35.0–36.9
  int swappedVotes = 0;
  for (final p in pts) {
    if (p.length < 2) continue;
    final a = p[0], b = p[1]; // a=lat?, b=lng?
    final aLatOk = a >= 33.0 && a <= 34.9;
    final bLngOk = b >= 35.0 && b <= 36.9;
    final swappedCandidate = (b >= 33.0 && b <= 34.9) && (a >= 35.0 && a <= 36.9);
    if (!aLatOk && swappedCandidate && !bLngOk) swappedVotes++;
  }
  return swappedVotes > (pts.length / 2);
}

static List<List<double>> _normalizeLebanonLatLng(List<List<double>> pts) {
  if (_looksSwappedForLebanon(pts)) {
    // swap each [x,y] -> [y,x]
    return pts.map((p) => p.length >= 2 ? <double>[p[1], p[0]] : p).toList();
  }
  return pts;
}
  // ---------- Blocking warmup (first run ONLY) ----------
  /// Downloads ALL Lebanon hexes once, saves to Hive, sets warmup flag,
  /// and returns the number of zones saved. Subsequent runs should **not**
  /// call this (guard in the caller).
  static Future<int> warmupAllLebanon() async {
    final meta = Hive.box('meta');
    if (meta.get(_kWarmupDone, defaultValue: false) == true) {
      return loadZones().length;
    }

    final res = await http.get(Uri.parse('$apiBase/hex_zones_lebanon'));
    if (res.statusCode != 200) {
      throw Exception('warmupAllLebanon failed: ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = (data['zones'] as List).cast<Map<String, dynamic>>();

    final upserts = <HexZone>[];
    for (final z in raw) {
      final id = z['zone_id'] as String;
      final colorHex = (z['color'] as String?) ?? '#00FF00';
      final colorValue = int.parse('0xFF${colorHex.replaceAll("#", "")}');
      final score = (z['score'] as num?)?.toDouble() ?? 0.0;
      final city = (z['city'] as String?) ?? '';
      final boundary = _parseBoundary(z['boundary']);

      upserts.add(HexZone(
        zoneId: id,
        boundary: boundary,
        colorValue: colorValue,
        score: score,
        city: city,
        updatedAt: DateTime.now(),
      ));
    }

    await saveZonesBatch(upserts);
    await meta.put(_kWarmupDone, true);
    return upserts.length;
  }

  // ---------- Targeted refresh: /hex_zones?lat=..&lng=.. ----------
  static Future<void> refreshCityByLatLng(
    double lat,
    double lng, {
    Duration ttl = const Duration(minutes: 20),
  }) async {
    final meta = Hive.box('meta');
    final box = Hive.box<HexZone>(hexBoxName);

    final res = await http.get(Uri.parse('$apiBase/hex_zones?lat=$lat&lng=$lng'));
    if (res.statusCode != 200) return;

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final city = (data['city'] as String?) ?? '';
    if (city.isEmpty) return;

    final key = '$_kLastCityRefreshPrefix$city';
    final lastIso = meta.get(key) as String?;
    if (lastIso != null) {
      final last = DateTime.tryParse(lastIso);
      if (last != null && DateTime.now().difference(last) < ttl) {
        return;
      }
    }

    final zones = (data['zones'] as List).cast<Map<String, dynamic>>();
    final map = <String, HexZone>{};

    for (final z in zones) {
      final id = z['zone_id'] as String;
      final colorHex = (z['color'] as String?) ?? '#00FF00';
      final colorValue = int.parse('0xFF${colorHex.replaceAll("#", "")}');
      final score = (z['score'] as num?)?.toDouble() ?? 0.0;
      final boundary = _parseBoundary(z['boundary']);

      final existing = box.get(id);
      if (existing == null) {
        map[id] = HexZone(
          zoneId: id,
          boundary: boundary,
          colorValue: colorValue,
          score: score,
          city: city,
          updatedAt: DateTime.now(),
        );
      } else {
        if (boundary.isNotEmpty) existing.boundary = boundary;
        existing.colorValue = colorValue;
        existing.score = score;
        if (city.isNotEmpty) existing.city = city;
        existing.updatedAt = DateTime.now();
        map[id] = existing;
      }
    }

    if (map.isNotEmpty) {
      await box.putAll(map);
    }
    await meta.put(key, DateTime.now().toIso8601String());
  }

  // ---------- boundary parser (string or list) ----------
  static List<List<double>> _parseBoundary(dynamic raw) {
  try {
    List<List<double>> pts;
    if (raw is String && raw.isNotEmpty) {
      final parsed = jsonDecode(raw) as List;
      pts = parsed
          .map<List<double>>(
              (p) => (p as List).map((x) => (x as num).toDouble()).toList())
          .toList();
    } else if (raw is List) {
      pts = raw
          .map<List<double>>(
              (p) => (p as List).map((x) => (x as num).toDouble()).toList())
          .toList();
    } else {
      return const <List<double>>[];
    }

    // ✅ fix potential (lng,lat) → (lat,lng)
    return _normalizeLebanonLatLng(pts);
  } catch (_) {
    return const <List<double>>[];
  }
}

}
