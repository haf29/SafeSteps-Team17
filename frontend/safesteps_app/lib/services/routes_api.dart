import 'dart:convert';
import 'package:http/http.dart' as http;

// ===================== Config =====================
// Use these at run time with --dart-define.
//   API_BASE_URL:   http://127.0.0.1:8000  (or your backend host)
//   API_PREFIX:     /api  (leave empty if your FastAPI has no prefix)
// Example (PowerShell):
// flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000 --dart-define=API_PREFIX= --dart-define=WEB_MAPS_ENABLED=true
const String _baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);
const String _prefix = String.fromEnvironment('API_PREFIX', defaultValue: '');

String _url(String path) {
  // joins base + optional prefix + path, avoiding double slashes
  final p = (_prefix.isEmpty) ? '' : (_prefix.startsWith('/') ? _prefix : '/$_prefix');
  final s = path.startsWith('/') ? path : '/$path';
  return '$_baseUrl$p$s';
}

// ===================== Models =====================
class LatLng {
  final double lat;
  final double lng;

  // Make it const so you can write: const LatLng(...)
  const LatLng({required this.lat, required this.lng});

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
}


class RouteRequest {
  final LatLng origin;
  final LatLng destination;
  final String? city;
  final int resolution; // 1..15 (default 9)
  final bool alternatives; // default true
  final String mode; // walking|driving|bicycling|transit
  final double? alpha; // 0..1

  RouteRequest({
    required this.origin,
    required this.destination,
    this.city,
    this.resolution = 9,
    this.alternatives = true,
    this.mode = 'walking',
    this.alpha,
  });

  Map<String, dynamic> toJson() => {
        'origin': origin.toJson(),
        'destination': destination.toJson(),
        'city': city,
        'resolution': resolution,
        'alternatives': alternatives,
        'mode': mode,
        'alpha': alpha,
      };
}

class ExitToSafetyRequest {
  final LatLng position;
  final String? city;
  final int resolution;
  final int maxRings;
  final String mode;
  final String? phone;
  final String? topicArn;
  final double? prevScore;
  final double upThreshold;
  final double downThreshold;
  final double minJump;

  ExitToSafetyRequest({
    required this.position,
    this.city,
    this.resolution = 9,
    this.maxRings = 4,
    this.mode = 'walking',
    this.phone,
    this.topicArn,
    this.prevScore,
    this.upThreshold = 7.0,
    this.downThreshold = 5.0,
    this.minJump = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'position': position.toJson(),
        'city': city,
        'resolution': resolution,
        'max_rings': maxRings,
        'mode': mode,
        'phone': phone,
        'topic_arn': topicArn,
        'prev_score': prevScore,
        'up_threshold': upThreshold,
        'down_threshold': downThreshold,
        'min_jump': minJump,
      };
}

class Score {
  final double avgSeverity;
  final double maxSeverity;
  final int samples;
  Score({required this.avgSeverity, required this.maxSeverity, required this.samples});
  factory Score.fromJson(Map<String, dynamic> j) => Score(
        avgSeverity: (j['avg_severity'] ?? 0).toDouble(),
        maxSeverity: (j['max_severity'] ?? 0).toDouble(),
        samples: (j['samples'] ?? 0) as int,
      );
}

class Candidate {
  final String summary;
  final int durationSec;
  final int distanceM;
  final List<String> hexes;
  final Score score;
  final double? cost;
  final String? encodedPolyline; // from raw.polyline.encodedPolyline

  Candidate({
    required this.summary,
    required this.durationSec,
    required this.distanceM,
    required this.hexes,
    required this.score,
    this.cost,
    this.encodedPolyline,
  });

  factory Candidate.fromJson(Map<String, dynamic> j) {
    String? enc;
    final raw = j['raw'];
    if (raw is Map && raw['polyline'] is Map && raw['polyline']['encodedPolyline'] is String) {
      enc = raw['polyline']['encodedPolyline'] as String;
    }
    return Candidate(
      summary: j['summary']?.toString() ?? 'route',
      durationSec: (j['duration_sec'] ?? 0) as int,
      distanceM: (j['distance_m'] ?? 0) as int,
      hexes: (j['hexes'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      score: Score.fromJson(j['score'] ?? const {}),
      cost: j['cost'] == null ? null : (j['cost'] as num).toDouble(),
      encodedPolyline: enc,
    );
  }
}

class SafestResponse {
  final Candidate chosen;
  final List<Candidate> candidates;
  final List<String> citiesUsed;
  final String? primaryCity;

  SafestResponse({
    required this.chosen,
    required this.candidates,
    required this.citiesUsed,
    this.primaryCity,
  });

  factory SafestResponse.fromJson(Map<String, dynamic> j) => SafestResponse(
        chosen: Candidate.fromJson(j['chosen']),
        candidates: (j['candidates'] as List).map((e) => Candidate.fromJson(e)).toList(),
        citiesUsed: (j['cities_used'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        primaryCity: j['primary_city']?.toString(),
      );
}

class ExitRouteBundle {
  final Candidate chosen;
  final List<Candidate> candidates;
  ExitRouteBundle({required this.chosen, required this.candidates});
  factory ExitRouteBundle.fromJson(Map<String, dynamic> j) => ExitRouteBundle(
        chosen: Candidate.fromJson(j['chosen']),
        candidates: (j['candidates'] as List).map((e) => Candidate.fromJson(e)).toList(),
      );
}

sealed class ExitResponse {}

class ExitNotFound extends ExitResponse {
  final String detail;
  ExitNotFound(this.detail);
}

class ExitSuccess extends ExitResponse {
  final String safeHex;
  final LatLng safeTarget;
  final ExitRouteBundle route;
  final String? snsMessageId;
  final String? snsError;

  ExitSuccess({
    required this.safeHex,
    required this.safeTarget,
    required this.route,
    this.snsMessageId,
    this.snsError,
  });

  factory ExitSuccess.fromJson(Map<String, dynamic> j) => ExitSuccess(
        safeHex: j['safe_hex'].toString(),
        safeTarget: LatLng(
          lat: (j['safe_target']['lat'] as num).toDouble(),
          lng: (j['safe_target']['lng'] as num).toDouble(),
        ),
        route: ExitRouteBundle.fromJson(j['route']),
        snsMessageId: j['sns_message_id']?.toString(),
        snsError: j['sns_error']?.toString(),
      );
}

// ===================== HTTP calls =====================
Exception _httpError(http.Response r) =>
    Exception('HTTP ${r.statusCode}: ${r.body.isNotEmpty ? r.body : r.reasonPhrase}');

Future<SafestResponse> postSafestRoute(RouteRequest req) async {
  final r = await http.post(
    Uri.parse(_url('/route/safest')),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(req.toJson()),
  );
  if (r.statusCode >= 400) throw _httpError(r);
  return SafestResponse.fromJson(jsonDecode(r.body));
}

Future<ExitResponse> postExitToSafety(ExitToSafetyRequest req) async {
  final r = await http.post(
    Uri.parse(_url('/route/exit_to_safety')),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(req.toJson()),
  );
  if (r.statusCode >= 400) throw _httpError(r);
  final j = jsonDecode(r.body) as Map<String, dynamic>;
  if (j['action'] == 'no_exit_needed_or_not_found') {
    return ExitNotFound(j['detail']?.toString() ?? 'No safe hex found.');
  }
  return ExitSuccess.fromJson(j);
}

// ===================== Utils =====================
String fmtDuration(int sec) {
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  final parts = <String>[];
  if (h > 0) parts.add('${h}h');
  if (m > 0) parts.add('${m}m');
  if (s > 0 || parts.isEmpty) parts.add('${s}s');
  return parts.join(' ');
}

/// Decode Google Encoded Polyline
List<LatLng> decodePolyline(String encoded) {
  final List<LatLng> points = [];
  int index = 0, lat = 0, lng = 0;

  int _decodeChunk() {
    int result = 0, shift = 0, b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  while (index < encoded.length) {
    lat += _decodeChunk();
    lng += _decodeChunk();
    points.add(LatLng(lat: lat / 1e5, lng: lng / 1e5));
  }
  return points;
}
