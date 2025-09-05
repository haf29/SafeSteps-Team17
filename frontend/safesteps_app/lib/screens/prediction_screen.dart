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

/// Model for a hex zone
class HexZone {
  final String zoneId;
  final List<List<double>> boundary;
  final double severity;

  HexZone({required this.zoneId, required this.boundary, required this.severity});
}

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  List<Polygon> polygons = [];
  bool loading = true;
  String error = "";

  static const String apiBase = 'http://51.20.9.164:8000';
  static const String apiEndpoint = '/zonesml/all';

  @override
  void initState() {
    super.initState();
    fetchZones();
  }

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
      final List<Polygon> newPolygons = [];

      for (var z in data) {
        final zoneId = z['zone_id'] as String;
        final severity = (z['severity'] as num).toDouble();
        final boundaryRaw = z['boundary'];
        final boundary = _parseBoundary(boundaryRaw);

        if (boundary.isEmpty) continue;

        final points = boundary.map((c) => LatLng(c[0], c[1])).toList();

        newPolygons.add(
          Polygon(
            points: points,
            color: severityToColor(severity).withOpacity(0.5),
            borderColor: Colors.black,
            borderStrokeWidth: 1.0,
          ),
        );
      }

      setState(() {
        polygons = newPolygons;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  /// Parse boundary from API (like HiveService)
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty
              ? Center(child: Text(error))
              : FlutterMap(
                  options: MapOptions(
                    initialCenter: polygons.isNotEmpty
                        ? polygons[0].points[0]
                        : LatLng(37.7749, -122.4194),
                    initialZoom: 12,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                      userAgentPackageName: "com.example.app",
                    ),
                    PolygonLayer(polygons: polygons),
                  ],
                ),
    );
  }
}