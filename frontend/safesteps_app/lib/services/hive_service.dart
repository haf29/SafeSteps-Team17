import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';
import '../models/hex_zone_model.dart';
import 'package:flutter/material.dart';

class HiveService {
  static const String hexBoxName = "hex_zones";
  static const String metaBoxName = "meta";
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://51.20.9.164:8000',
  );

  // TTL per tile
  static const Duration tileTTL = Duration(minutes: 20);

  static Future<void> initHive() async {
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(HexZoneAdapter());
    await Future.wait([Hive.openBox<HexZone>(hexBoxName), Hive.openBox(metaBoxName)]);
  }

  // ---------- Tiles ----------

  static String tileIdFor(double lat, double lng, {double size = 0.1}) {
    final latKey = (lat / size).floorToDouble() * size;
    final lngKey = (lng / size).floorToDouble() * size;
    return "${latKey.toStringAsFixed(1)}_${lngKey.toStringAsFixed(1)}";
  }

  static List<String> tileIdsForRect(double south, double west, double north, double east,
      {double size = 0.1}) {
    final ids = <String>{};
    if (north < south) {
      final t = south;
      south = north;
      north = t;
    }
    if (east < west) {
      final t = west;
      west = east;
      east = t;
    }

    double lat = (south / size).floorToDouble() * size;
    for (; lat <= north + 1e-9; lat += size) {
      double lng = (west / size).floorToDouble() * size;
      for (; lng <= east + 1e-9; lng += size) {
        ids.add(tileIdFor(lat, lng, size: size));
      }
    }
    return ids.toList();
  }

  static List<HexZone> loadZonesForTiles(List<String> tileIds) {
    final box = Hive.box<HexZone>(hexBoxName);
    if (tileIds.isEmpty) return const [];
    final set = tileIds.toSet();
    return box.values.where((z) => set.contains(z.tileId)).toList();
  }

  static Future<void> saveZonesBatch(List<HexZone> zones) async {
    final box = Hive.box<HexZone>(hexBoxName);
    final meta = Hive.box(metaBoxName);

    for (final z in zones) {
      if ((z.tileId).isEmpty && z.boundary.isNotEmpty) {
        final c = _centroid(z.boundary);
        z.tileId = tileIdFor(c[0], c[1]);
      }
    }
    final map = {for (var z in zones) z.zoneId: z};
    await box.putAll(map);

    // Update tile last fetch
    final nowIso = DateTime.now().toIso8601String();
    for (var z in zones) {
      meta.put('tile_last_update_${z.tileId}', nowIso);
    }
  }

  static bool tileExpired(String tileId) {
    final meta = Hive.box(metaBoxName);
    final lastIso = meta.get('tile_last_update_$tileId') as String?;
    if (lastIso == null) return true;
    final last = DateTime.tryParse(lastIso);
    if (last == null) return true;
    return DateTime.now().difference(last) > tileTTL;
  }

  // ---------- Fetch from backend ----------

  static Future<void> fetchZonesByBBox(
      double minLat, double minLng, double maxLat, double maxLng) async {
    try {
      final url =
          Uri.parse('$apiBase/hex_zones_bbox?min_lat=$minLat&min_lng=$minLng&max_lat=$maxLat&max_lng=$maxLng&page_limit=1000');
      final res = await http.get(url);
      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final zonesRaw = (data['zones'] as List).cast<Map<String, dynamic>>();
      final zones = <HexZone>[];

      for (var z in zonesRaw) {
        final id = z['zone_id'] as String;
        final colorHex = (z['color'] as String?) ?? '#00FF00';
        final colorValue = int.parse('0xFF${colorHex.replaceAll("#", "")}');
        final score = (z['score'] as num?)?.toDouble() ?? 0.0;
        final boundary = _parseBoundary(z['boundary']);
        final tileId = boundary.isNotEmpty ? tileIdFor(_centroid(boundary)[0], _centroid(boundary)[1]) : '';

        zones.add(HexZone(
          zoneId: id,
          boundary: boundary,
          colorValue: colorValue,
          score: score,
          city: z['city'] ?? '',
          tileId: tileId,
          updatedAt: DateTime.now(),
        ));
      }

      if (zones.isNotEmpty) await saveZonesBatch(zones);
    } catch (e) {
      debugPrint('fetchZonesByBBox error: $e');
    }
  }

  // ---------- Utils ----------

  static List<double> _centroid(List<List<double>> pts) {
    double lat = 0, lng = 0;
    for (var p in pts) {
      lat += p[0];
      lng += p[1];
    }
    final n = pts.length.toDouble();
    return [lat / n, lng / n];
  }

  static List<List<double>> _parseBoundary(dynamic raw) {
    if (raw == null) return const [];
    try {
      List<List<double>> pts;
      if (raw is String && raw.isNotEmpty) {
        final parsed = jsonDecode(raw) as List;
        pts = parsed.map<List<double>>((p) => (p as List).map((x) => (x as num).toDouble()).toList()).toList();
      } else if (raw is List) {
        pts = raw.map<List<double>>((p) => (p as List).map((x) => (x as num).toDouble()).toList()).toList();
      } else {
        return const [];
      }
      return pts;
    } catch (_) {
      return const [];
    }
  }
}