import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

part 'hex_zone_model.g.dart';

@HiveType(typeId: 0)
class HexZone extends HiveObject {
  @HiveField(0)
  String zoneId;

  @HiveField(1)
  List<List<double>> boundary; // [[lng, lat], ...]

  @HiveField(2)
  int colorValue; // Color stored as int

  HexZone({
    required this.zoneId,
    required this.boundary,
    required this.colorValue,
  });

  // Convert to FlutterMap Polygon
  Polygon toPolygon() {
    return Polygon(
      points: boundary.map((coord) => LatLng(coord[1], coord[0])).toList(),
      color: Color(colorValue).withOpacity(0.3),
      borderColor: Color(colorValue),
      borderStrokeWidth: 2,
    );
  }
}
