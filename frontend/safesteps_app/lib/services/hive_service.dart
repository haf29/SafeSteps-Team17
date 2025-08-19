import 'package:hive/hive.dart';
import '../models/hex_zone_model.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class HiveService {
  static const String hexBoxName = "hex_zones";

  // Initialize Hive box
  static Future<void> initHive() async {
    Hive.registerAdapter(HexZoneAdapter());
    await Hive.openBox<HexZone>(hexBoxName);
  }

  // Save all zones
  static Future<void> saveZones(List<HexZone> zones) async {
    var box = Hive.box<HexZone>(hexBoxName);
    await box.clear(); // Clear old data
    for (var z in zones) {
      await box.put(z.zoneId, z);
    }
  }

  // Load all zones
  static List<HexZone> loadZones() {
    var box = Hive.box<HexZone>(hexBoxName);
    return box.values.toList();
  }

  // Update colors only
  static Future<void> updateColorsFromBackend(String backendUrl) async {
    try {
      var box = Hive.box<HexZone>(hexBoxName);
      final response = await http.get(Uri.parse('$backendUrl/colors'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> zones = data['zones'];
        for (var z in zones) {
          final zone = box.get(z['zone_id']);
          if (zone != null) {
            zone.colorValue = int.parse('0xFF${z['color'].replaceAll("#", "")}');
            await zone.save();
          }
        }
      }
    } catch (e) {
      print("Error updating colors: $e");
    }
  }
}
