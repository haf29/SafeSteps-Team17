import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

/// Convert severity score into a color
Color severityToColor(double score) {
  if (score < 1) return const Color(0xFF00FF00); // Green
  if (score < 2) return const Color(0xFFFFFF00); // Yellow
  return const Color(0xFFFF0000); // Red
}

/// HexZone model
class HexZone {
  final String zoneId;
  final List<LatLng> points;
  final double severity;

  HexZone({required this.zoneId, required this.points, required this.severity});
}

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  List<HexZone> zones = [];
  bool loading = true;
  String error = "";
  final MapController mapController = MapController();

  static const String apiBase = 'http://51.20.9.164:8000';
  static const String apiEndpoint = '/zonesml/all';

  @override
  void initState() {
    super.initState();
    fetchZones();
  }

  /// Fetch zones and build HexZone list
  Future<void> fetchZones() async {
    try {
      final url = Uri.parse('$apiBase$apiEndpoint');
      final res = await http.get(url);

      if (res.statusCode != 200) {
        setState(() {
          error = 'Failed to fetch zones: ${res.statusCode}';
          loading = false;
        });
        return;
      }

      final List data = jsonDecode(res.body) as List;
      final List<HexZone> newZones = [];

      for (var z in data) {
        final zoneId = z['zone_id'].toString(); // ensure string
        final severity = (z['severity'] as num).toDouble();
        final boundaryRaw = z['boundary'];
        final points = _parseBoundary(boundaryRaw)
            .map((c) => LatLng(c[0], c[1]))
            .toList();

        if (points.isNotEmpty) {
          newZones.add(HexZone(zoneId: zoneId, points: points, severity: severity));
        }
      }

      setState(() {
        zones = newZones;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  /// Parse boundary from API
  List<List<double>> _parseBoundary(dynamic raw) {
    if (raw == null) return const [];
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
        return const [];
      }
      return pts;
    } catch (_) {
      return const [];
    }
  }

  /// Point-in-polygon check (ray-casting)
  bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    int i, j = polygon.length - 1;
    bool oddNodes = false;
    for (i = 0; i < polygon.length; i++) {
      if ((polygon[i].latitude < point.latitude &&
              polygon[j].latitude >= point.latitude ||
          polygon[j].latitude < point.latitude &&
              polygon[i].latitude >= point.latitude) &&
          (polygon[i].longitude +
                  (point.latitude - polygon[i].latitude) /
                      (polygon[j].latitude - polygon[i].latitude) *
                      (polygon[j].longitude - polygon[i].longitude) <
              point.longitude)) {
        oddNodes = !oddNodes;
      }
      j = i;
    }
    return oddNodes;
  }

  /// Show input dialog and call predict-zone API
  Future<void> _predictForZone(String zoneId) async {
    final controller = TextEditingController();

    final nDays = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Enter number of days"),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                final val = int.tryParse(controller.text);
                if (val != null && val > 0) Navigator.pop(ctx, val);
              },
              child: const Text("Submit"),
            ),
          ],
        );
      },
    );

    if (nDays == null) return;

    try {
      final url = Uri.parse('$apiBase/predict-zone');
      final res = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"zone_id": int.parse(zoneId), "n_days": nDays}), // send string
      );

      if (res.statusCode == 200) {
        await fetchZones();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Prediction successful! Map updated.")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Prediction failed: ${res.body}")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  /// Helper widget for legend
  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty
              ? Center(child: Text(error))
              : Stack(
                  children: [
                    FlutterMap(
                      mapController: mapController,
                      options: MapOptions(
                        initialCenter: zones.isNotEmpty
                            ? zones[0].points[0]
                            : LatLng(37.7749, -122.4194),
                        initialZoom: 12,
                        onTap: (tapPos, latLng) {
                          for (var zone in zones) {
                            if (_pointInPolygon(latLng, zone.points)) {
                              _predictForZone(zone.zoneId);
                              break;
                            }
                          }
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                          userAgentPackageName: "com.example.app",
                        ),
                        PolygonLayer(
                          polygons: zones
                              .map((z) => Polygon(
                                    points: z.points,
                                    color:
                                        severityToColor(z.severity).withOpacity(0.5),
                                    borderColor: Colors.black,
                                    borderStrokeWidth: 1.0,
                                  ))
                              .toList(),
                        ),
                      ],
                    ),

                    // Bottom-left legend
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(2, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLegendItem(Colors.green, "Low"),
                            const SizedBox(height: 4),
                            _buildLegendItem(Colors.yellow, "Medium"),
                            const SizedBox(height: 4),
                            _buildLegendItem(Colors.red, "High"),
                          ],
                        ),
                      ),
                    ),

                    // Top info message
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        color: Colors.blue.shade100,
                        child: const Text(
                          "ℹ️ Tap on a hexagon to predict severity colors for future days.",
                          style: TextStyle(fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}