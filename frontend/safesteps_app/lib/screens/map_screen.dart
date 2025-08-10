import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Position? currentPosition;
  List<Marker> markers = [];
  List<Polygon> polygons = [];
  final double _defaultZoom = 14.0;
  bool _loading = true;
  bool _backendError = false; // Track if backend failed

  // Backend URL
  final String backendUrl = "http://localhost:8000";

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  /// Get current user location
  Future<void> _getCurrentLocation() async {
    setState(() {
      _loading = true;
      _backendError = false;
    });

    var permission = await Permission.location.request();

    if (permission.isGranted) {
      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        setState(() {
          currentPosition = position;
          markers = [
            Marker(
              width: 80.0,
              height: 80.0,
              point: LatLng(position.latitude, position.longitude),
              child: const Icon(Icons.location_on, color: Colors.red, size: 40),
            ),
          ];
        });

        // Only after we get location, fetch zones
        await _fetchHexZones(position.latitude, position.longitude);
      } catch (e) {
        print('Error getting location: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
        setState(() => _loading = false);
      }
    } else {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission denied')),
      );
    }
  }

  /// Fetch hexagonal zones from FastAPI backend
  Future<void> _fetchHexZones(double lat, double lng) async {
    final url = Uri.parse('$backendUrl/hex_zones?lat=$lat&lng=$lng');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
      final List<dynamic> zonesData = jsonResponse['zones'];

      List<Polygon> newPolygons = zonesData.map((hex) {
        List<LatLng> points = (hex['boundary'] as List)
            .map((coord) => LatLng(coord[0], coord[1]))
            .toList();

        String colorHex = hex['color'].replaceAll("#", "");
        Color polygonColor = Color(int.parse("0xFF$colorHex"));

        return Polygon(
          points: points,
          color: polygonColor.withOpacity(0.3),
          borderColor: polygonColor,
          borderStrokeWidth: 2,
        );
      }).toList();

      setState(() {
        polygons = newPolygons;
        _loading = false; // Stop loading only after backend data arrives
      });
    } else {
      print('Failed to fetch hex zones: ${response.statusCode}');
      setState(() {
        _backendError = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeSteps Map'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 6,
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              icon: const Icon(Icons.report, size: 20),
              label: const Text("Report", style: TextStyle(fontSize: 16)),
              onPressed: () {
                Navigator.pushNamed(context, '/report');
              },
            ),
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _backendError
              ? const Center(
                  child: Text(
                    "Failed to load data from backend.",
                    style: TextStyle(fontSize: 16, color: Colors.red),
                  ),
                )
              : currentPosition == null || polygons.isEmpty
                  ? const Center(child: Text("No map data available."))
                  : Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: FlutterMap(
                          options: MapOptions(
                            center: LatLng(
                              currentPosition!.latitude,
                              currentPosition!.longitude,
                            ),
                            zoom: _defaultZoom,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                              subdomains: const ['a', 'b', 'c'],
                              userAgentPackageName:
                                  'com.example.safesteps_app',
                            ),
                            PolygonLayer(polygons: polygons),
                            MarkerLayer(markers: markers),
                          ],
                        ),
                      ),
                    ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 12.0, right: 4.0),
        child: Card(
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          child: FloatingActionButton(
            onPressed: _getCurrentLocation,
            backgroundColor: Colors.indigo,
            child: const Icon(Icons.my_location),
          ),
        ),
      ),
    );
  }
}