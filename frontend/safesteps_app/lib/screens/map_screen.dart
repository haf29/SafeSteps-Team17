import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../services/hive_service.dart';
import '../models/hex_zone_model.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Position? currentPosition;
  List<Polygon> polygons = [];
  List<Marker> markers = [];
  final double _defaultZoom = 9.0; // reserved if you want to use later
  bool _loading = true;
  Timer? _colorTimer;

  /// For direct HTTP calls from this screen (HiveService already uses 127.0.0.1)
  final String backendUrl = 'http://127.0.0.1:8000';

  @override
  void initState() {
    super.initState();
    initMap();
  }

  @override
  void dispose() {
    _colorTimer?.cancel();
    super.dispose();
  }

  Future<void> initMap() async {
    await HiveService.initHive();

    // Try cached zones first
    final cachedZones = HiveService.loadZones();
    if (cachedZones.isNotEmpty) {
      setState(() {
        polygons = cachedZones.map(_hexToPolygon).toList();
        _loading = false;
      });
    } else {
      // Warmup (bulk) if cache empty
      await _fetchAllZones();
    }

    // Get GPS and refresh current city
    await _getCurrentLocation();

    // Periodic refresh of current city severities/colors
    _colorTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      if (currentPosition == null) return;
      await HiveService.refreshCityByLatLng(
        currentPosition!.latitude,
        currentPosition!.longitude,
      );
      final updated = HiveService.loadZones();
      setState(() {
        polygons = updated.map(_hexToPolygon).toList();
      });
    });
  }

  Future<void> _fetchAllZones() async {
    try {
      final response =
          await http.get(Uri.parse('$backendUrl/hex_zones_lebanon'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<HexZone> zones = (data['zones'] as List)
            .map<HexZone>((z) => HexZone(
                  zoneId: z['zone_id'] as String,
                  boundary: (z['boundary'] as List?)
                          ?.map<List<double>>(
                              (p) => (p as List).map((x) => (x as num).toDouble()).toList())
                          .toList() ??
                      const <List<double>>[],
                  colorValue: int.parse(
                      '0xFF${(z['color'] as String? ?? '#00FF00').replaceAll("#", "")}'),
                  score: (z['score'] as num?)?.toDouble() ?? 0.0,
                  city: (z['city'] as String?) ?? '',
                ))
            .toList();

        await HiveService.saveZones(zones);
        setState(() {
          polygons = zones.map(_hexToPolygon).toList();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('Error fetching all zones: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() => currentPosition = pos);

      // Refresh the severities for the user's current city
      await HiveService.refreshCityByLatLng(pos.latitude, pos.longitude);

      // Update polygons after refresh
      final updated = HiveService.loadZones();
      setState(() {
        polygons = updated.map(_hexToPolygon).toList();
      });
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  Polygon _hexToPolygon(HexZone z) {
    final pts = z.boundary.map((p) => LatLng(p[0], p[1])).toList();
    final color = Color(z.colorValue);
    return Polygon(
      points: pts,
      // some versions of flutter_map don't support `isFilled`; fill is implied via color opacity
      color: color.withOpacity(0.35),
      borderColor: color.withOpacity(0.9),
      borderStrokeWidth: 1.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lebanon Hex Map'),
        backgroundColor: Colors.indigo,
      ),
      body: _loading || currentPosition == null
          ? const Center(child: CircularProgressIndicator())
          : FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(
                  currentPosition!.latitude,
                  currentPosition!.longitude,
                ),
                initialZoom: 13.0,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.example.safesteps_app',
                ),
                PolygonLayer(polygons: polygons),
                MarkerLayer(markers: markers),
              ],
            ),
    );
  }
}
