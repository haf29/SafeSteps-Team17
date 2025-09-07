import 'dart:convert';
import 'package:http/http.dart' as http;

// ===================== Config =====================
// Use these at run time with --dart-define.
//   API_BASE_URL:   http://127.0.0.1:8000  (or your backend host)
//   API_PREFIX:     /api  (leave empty if your FastAPI has no prefix)
// Example (PowerShell):
// flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000 --dart-define=API_PREFIX= --dart-define=WEB_MAPS_ENABLED=true
const  String _API_BASE="http://51.20.9.164:8000";
const String _baseUrl = String.fromEnvironment(
  '_API_BASE',
  defaultValue: 'http://51.20.9.164:8000',
);
const String _prefix = String.fromEnvironment('API_PREFIX', defaultValue: '');

const String _ROUTE_PATH = '/route/safest';           // ← fix
const String _EXIT_PATH  = '/route/exit_to_safety';   // ← fix

// ===== Small utils =====
T? _path<T>(Map obj, List keys) {
  dynamic cur = obj;
  for (final k in keys) {
    if (cur is Map && cur.containsKey(k)) {
      cur = cur[k];
    } else {
      return null;
    }
  }
  return cur as T?;
}

num? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

String fmtDuration(int seconds) {
  final d = Duration(seconds: seconds);
  final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (d.inHours > 0) return '${d.inHours}:$mm:$ss';
  return '${d.inMinutes}:$ss';
}

// ===== Core models =====
class LatLng {
  final double lat;
  final double lng;
  const LatLng({required this.lat, required this.lng});

  factory LatLng.fromJson(dynamic j) {
    if (j is Map) {
      final la = _num(j['lat'])?.toDouble();
      final ln = _num(j['lng'])?.toDouble() ?? _num(j['lon'])?.toDouble();
      if (la != null && ln != null) return LatLng(lat: la, lng: ln);
    }
    if (j is List && j.length >= 2) {
      return LatLng(
        lat: _num(j[0])!.toDouble(),
        lng: _num(j[1])!.toDouble(),
      );
    }
    throw FormatException('Bad LatLng json: $j');
  }

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
}

class Score {
  final double avgSeverity;
  final double maxSeverity;
  final int samples;

  Score({required this.avgSeverity, required this.maxSeverity, required this.samples});

  factory Score.fromJson(Map<String, dynamic> j) => Score(
        avgSeverity: (_num(j['avg_severity']) ?? _num(j['avgSeverity']) ?? 0).toDouble(),
        maxSeverity: (_num(j['max_severity']) ?? _num(j['maxSeverity']) ?? 0).toDouble(),
        samples: (_num(j['samples']) ?? 0).toInt(),
      );
}

class Candidate {
  final String summary;
  final int durationSec;
  final int distanceM;
  final Score score;

  /// ✅ Preferred for drawing: backend-decoded polyline points.
  final List<LatLng>? polylinePoints;

  /// Optional fallback string (may be polyline5/6 or provider-specific).
  final String? encodedPolyline;

  /// Optional freeform raw payload (for debugging)
  final Map<String, dynamic>? raw;

  Candidate({
    required this.summary,
    required this.durationSec,
    required this.distanceM,
    required this.score,
    this.polylinePoints,
    this.encodedPolyline,
    this.raw,
  });

  factory Candidate.fromJson(Map<String, dynamic> j) {
    // 1) parse polyline points from either snake/camel or nested shapes
    List<LatLng>? pts;
    final pp = j['polyline_points'] ?? j['polylinePoints'];
    if (pp is List) {
      pts = pp
          .map((e) {
            try {
              return LatLng.fromJson(e);
            } catch (_) {
              return null;
            }
          })
          .whereType<LatLng>()
          .toList();
      if (pts.isEmpty) pts = null;
    }

    // 2) encoded polyline can be top-level or nested in raw.polyline.encodedPolyline
    String? enc = j['encodedPolyline'] as String?;
    final raw = (j['raw'] is Map) ? (j['raw'] as Map).cast<String, dynamic>() : null;
    enc ??= _path<String>(raw ?? const {}, ['polyline', 'encodedPolyline']);

    return Candidate(
      summary: (j['summary'] ?? '').toString(),
      durationSec: (_num(j['duration_sec']) ?? _num(j['durationSec']) ?? 0).toInt(),
      distanceM: (_num(j['distance_m']) ?? _num(j['distanceM']) ?? 0).toInt(),
      score: Score.fromJson((j['score'] as Map).cast<String, dynamic>()),
      polylinePoints: pts,
      encodedPolyline: enc,
      raw: raw,
    );
  }
}

class SafestResponse {
  final Candidate chosen;
  final List<Candidate> candidates;

  SafestResponse({required this.chosen, required this.candidates});

  factory SafestResponse.fromJson(Map<String, dynamic> j) {
    final chosenJ = (j['chosen'] ?? j['route']?['chosen']) as Map?;
    final candList = (j['candidates'] ??
            j['route']?['candidates'] ??
            j['alternatives']) as List? ??
        const [];
    return SafestResponse(
      chosen: Candidate.fromJson((chosenJ ?? const {}).cast<String, dynamic>()),
      candidates: candList
          .map((e) => Candidate.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

// Exit API shapes
class ExitRoute {
  final Candidate chosen;
  final List<Candidate> candidates;
  ExitRoute({required this.chosen, required this.candidates});

  factory ExitRoute.fromJson(Map<String, dynamic> j) => ExitRoute(
        chosen: Candidate.fromJson((j['chosen'] as Map).cast<String, dynamic>()),
        candidates: ((j['candidates'] as List?) ?? const [])
            .map((e) => Candidate.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

abstract class ExitResponse {
  const ExitResponse();
}

class ExitSuccess extends ExitResponse {
  final String safeHex;
  final LatLng safeTarget;
  final ExitRoute route;
  final String? snsMessageId;
  final String? snsError;

  const ExitSuccess({
    required this.safeHex,
    required this.safeTarget,
    required this.route,
    this.snsMessageId,
    this.snsError,
  });

  factory ExitSuccess.fromJson(Map<String, dynamic> j) => ExitSuccess(
        safeHex: (j['safe_hex'] ?? j['safeHex']).toString(),
        safeTarget: LatLng.fromJson(j['safe_target'] ?? j['safeTarget']),
        route: ExitRoute.fromJson((j['route'] as Map).cast<String, dynamic>()),
        snsMessageId: j['snsMessageId'] as String?,
        snsError: j['snsError'] as String?,
      );
}

class ExitNotFound extends ExitResponse {
  final String detail;
  const ExitNotFound(this.detail);

  factory ExitNotFound.fromJson(Map<String, dynamic> j) =>
      ExitNotFound((j['detail'] ?? 'No safe route found').toString());
}

// ===== Request payloads =====
class RouteRequest {
  final LatLng origin;
  final LatLng destination;
  final String? city;
  final int resolution;
  final bool alternatives;
  final String mode; // walking | cycling | driving
  final double alpha;

  RouteRequest({
    required this.origin,
    required this.destination,
    required this.resolution,
    required this.alternatives,
    required this.mode,
    required this.alpha,
    this.city,
  });

  Map<String, dynamic> toJson() => {
        'origin': origin.toJson(),
        'destination': destination.toJson(),
        if (city != null) 'city': city,
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
  final double? prevScore;
  final double upThreshold;
  final double downThreshold;
  final double minJump;
  final String? phone;
  final String? topicArn;

  ExitToSafetyRequest({
    required this.position,
    required this.resolution,
    required this.maxRings,
    required this.mode,
    required this.upThreshold,
    required this.downThreshold,
    required this.minJump,
    this.city,
    this.prevScore,
    this.phone,
    this.topicArn,
  });

  Map<String, dynamic> toJson() => {
        'position': position.toJson(),
        if (city != null) 'city': city,
        'resolution': resolution,
        'max_rings': maxRings,
        'mode': mode,
        if (prevScore != null) 'prev_score': prevScore,
        'up_threshold': upThreshold,
        'down_threshold': downThreshold,
        'min_jump': minJump,
        if (phone != null) 'phone': phone,
        if (topicArn != null) 'topicArn': topicArn,
      };
}

// ===== HTTP calls =====
Future<SafestResponse> postSafestRoute(RouteRequest req) async {
  final uri = Uri.parse('$_API_BASE$_ROUTE_PATH');
  final res = await http
      .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(req.toJson()))
      .timeout(const Duration(seconds: 25));

  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('Route error ${res.statusCode}: ${res.body}');
  }
  final j = jsonDecode(res.body) as Map<String, dynamic>;
  // The backend may wrap the response; try common shapes.
  final payload = (j['result'] is Map) ? (j['result'] as Map).cast<String, dynamic>() : j;
  return SafestResponse.fromJson(payload);
}

Future<ExitResponse> postExitToSafety(ExitToSafetyRequest req) async {
  final uri = Uri.parse('$_API_BASE$_EXIT_PATH');
  final res = await http
      .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(req.toJson()))
      .timeout(const Duration(seconds: 25));

  if (res.statusCode == 404) {
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ExitNotFound.fromJson(j);
  }
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('Exit error ${res.statusCode}: ${res.body}');
  }

  final j = jsonDecode(res.body) as Map<String, dynamic>;
  final payload = (j['result'] is Map) ? (j['result'] as Map).cast<String, dynamic>() : j;

  // Some backends use {status:'ok', data:{...}}
  final data = (payload['data'] is Map)
      ? (payload['data'] as Map).cast<String, dynamic>()
      : payload;

  return ExitSuccess.fromJson(data);
}