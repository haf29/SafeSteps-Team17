import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'report_screen.dart';

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
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  /// Get current user location
  Future<void> _getCurrentLocation() async {
    setState(() {
      _loading = true;
      _errorMessage = '';
    });

    try {
      var permission = await Permission.location.request();

      if (permission.isGranted) {
        // Get user location
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
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      'You are here',
                      style: TextStyle(
                        color: Color(0xFF1E3A8A),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.location_on,
                    color: Color(0xFF1E3A8A),
                    size: 40,
                  ),
                ],
              ),
            ),
          ];
        });

        // Generate demo safety zones
        _generateDemoZones(position);
      } else {
        setState(() {
          _errorMessage = 'Location permission denied. Please enable it in settings.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error getting location. Please try again.';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  /// Generate demo safety zones around the user's location
  void _generateDemoZones(Position position) {
    final random = math.Random();
    final List<Map<String, dynamic>> demoZones = [];

    // Generate 10 random zones
    for (int i = 0; i < 10; i++) {
      // Random offsets between -0.01 and 0.01 (roughly 1km)
      double latOffset = (random.nextDouble() - 0.5) * 0.02;
      double lngOffset = (random.nextDouble() - 0.5) * 0.02;

      // Random safety level (0-2: safe, 3-6: moderate, 7-10: high risk)
      int safetyLevel = random.nextInt(10);
      String color;
      if (safetyLevel <= 2) {
        color = '#4CAF50'; // Green for safe
      } else if (safetyLevel <= 6) {
        color = '#FFC107'; // Yellow for moderate
      } else {
        color = '#F44336'; // Red for high risk
      }

      // Create hexagon-like shape
      List<List<double>> boundary = [];
      int sides = 6;
      double radius = 0.003 + random.nextDouble() * 0.002; // Random size
      for (int j = 0; j < sides; j++) {
        double angle = (j * 2 * math.pi / sides);
        double lat = position.latitude + latOffset + radius * math.cos(angle);
        double lng = position.longitude + lngOffset + radius * math.sin(angle);
        boundary.add([lat, lng]);
      }
      // Close the polygon
      boundary.add(boundary[0]);

      demoZones.add({
        'boundary': boundary,
        'color': color,
      });
    }

    // Convert to polygons
    List<Polygon> newPolygons = demoZones.map((zone) {
      List<LatLng> points = (zone['boundary'] as List)
          .map((coord) => LatLng(coord[0], coord[1]))
          .toList();

      String colorHex = zone['color'].replaceAll("#", "");
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
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeSteps Map'),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        elevation: 2,
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ReportScreen()),
                );
              },
              icon: const Icon(Icons.report, size: 24),
              label: const Text(
                'Report',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 4,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading map...'),
                    ],
                  ),
                )
              : _errorMessage.isNotEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_off,
                              size: 64,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _getCurrentLocation,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Try Again'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E3A8A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : currentPosition == null
                      ? const Center(child: Text("Location unavailable"))
                      : ClipRRect(
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
          // Demo Mode Indicator
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200] ?? Colors.blue),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700] ?? Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Demo Mode",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700] ?? Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Safety zones are simulated for demonstration purposes.",
                          style: TextStyle(
                            color: Colors.blue[700] ?? Colors.blue,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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