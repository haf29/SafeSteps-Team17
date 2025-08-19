import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/hive_service.dart';
import '../models/hex_zone_model.dart';
import 'package:http/http.dart' as http;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Position? currentPosition;
  List<Polygon> polygons = [];
  List<Marker> markers = [];
  final double _defaultZoom = 9.0;
  bool _loading = true;
  Timer? _colorTimer;
  final String backendUrl = "http://localhost:8000";

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

    final cachedZones = HiveService.loadZones();
    if (cachedZones.isNotEmpty) {
      setState(() {
        polygons = cachedZones.map((z) => z.toPolygon()).toList();
        _loading = false;
      });
    } else {
      await _fetchAllZones();
    }

    _getCurrentLocation();

    // auto-refresh colors
    _colorTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      await HiveService.updateColorsFromBackend(backendUrl);
      final updatedZones = HiveService.loadZones();
      setState(() {
        polygons = updatedZones.map((z) => z.toPolygon()).toList();
      });
    });
  }

  Future<void> _fetchAllZones() async {
    try {
      final response = await http.get(Uri.parse('$backendUrl/all_zones'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<HexZone> zones = (data['zones'] as List).map<HexZone>((z) {
          return HexZone(
            zoneId: z['zone_id'],
            boundary: List<List<double>>.from(z['boundary']),
            colorValue: int.parse('0xFF${z['color'].replaceAll("#", "")}'),
          );
        }).toList();

        await HiveService.saveZones(zones);
        setState(() {
          polygons = zones.map((z) => z.toPolygon()).toList();
          _loading = false;
        });
      }
    } catch (e) {
      print("Error fetching all zones: $e");
      setState(() => _loading = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        currentPosition = position;
        markers = [
          Marker(
            width: 40,
            height: 40,
            point: LatLng(position.latitude, position.longitude),
            child: const Icon(Icons.arrow_drop_up, size: 40, color: Colors.red),
          ),
        ];
      });
    } catch (e) {
      print("Error getting location: $e");
    }
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
                  ), // Center on user
                  initialZoom: 13.0, // Closer zoom when user is found
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c'],
                    userAgentPackageName: 'com.example.safesteps_app',
                  ),
                  PolygonLayer(
                    polygons: polygons,
                  ),
                  MarkerLayer(
                    markers: markers,
                  ),
                ],
              ),
      );
    }
}

