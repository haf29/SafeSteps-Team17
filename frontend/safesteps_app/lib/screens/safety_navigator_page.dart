// lib/screens/safety_navigator_page.dart
import 'package:flutter/services.dart'; // for Clipboard in debug panel

import 'dart:async';
import 'dart:convert';
import 'dart:math' show min, max, cos, sin, atan2, sqrt;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as gc;
import 'package:http/http.dart' as http;

import '../services/routes_api.dart';

// ===== bounds of Lebanon =====
const double _LEB_MIN_LAT = 33.046;
const double _LEB_MAX_LAT = 34.693;
const double _LEB_MIN_LNG = 35.098;
const double _LEB_MAX_LNG = 36.623;
const String _ORS_KEY = "eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6ImJjZWYwNTc1YzgwNzRiZTRiOWI1ZjU3ZmE4MWFkMmVkIiwiaCI6Im11cm11cjY0In0=";
final gmaps.LatLngBounds _LB_BOUNDS = gmaps.LatLngBounds(
  southwest: const gmaps.LatLng(_LEB_MIN_LAT, _LEB_MIN_LNG),
  northeast: const gmaps.LatLng(_LEB_MAX_LAT, _LEB_MAX_LNG),
);

bool _inLebanon(double lat, double lng) =>
    lat >= _LEB_MIN_LAT && lat <= _LEB_MAX_LAT && lng >= _LEB_MIN_LNG && lng <= _LEB_MAX_LNG;

// web maps toggle
const bool _WEB_MAPS_ENABLED = bool.fromEnvironment('WEB_MAPS_ENABLED', defaultValue: false);

// Google API key
const String _GMAPS_KEY = String.fromEnvironment('GEOCODING_API_KEY', defaultValue: '');

// OSM endpoints
const String _OSM_SEARCH = 'https://nominatim.openstreetmap.org/search';
const String _OSM_REVERSE = 'https://nominatim.openstreetmap.org/reverse';

// quick cities
class _City {
  final String name;
  final double lat;
  final double lng;
  const _City(this.name, this.lat, this.lng);
}
const List<_City> _quick = <_City>[
  _City('Beirut', 33.8938, 35.5018),
  _City('Tripoli', 34.4333, 35.8333),
  _City('Sidon', 33.5570, 35.3720),
  _City('Tyre', 33.2730, 35.1930),
  _City('Byblos', 34.1210, 35.6510),
  _City('Zahle', 33.8460, 35.9020),
  _City('Baalbek', 34.0050, 36.2180),
];

class _PlacePred { final String desc, placeId; _PlacePred(this.desc, this.placeId); }

class _Poi {
  final String name;
  final String? placeId;
  final LatLng loc;
  final String secondary;
  final double distanceM;
  _Poi({required this.name, this.placeId, required this.loc, required this.secondary, required this.distanceM});
}

enum PickTarget { origin, destination, position }

class SafetyNavigatorPage extends StatefulWidget {
  const SafetyNavigatorPage({super.key});
  @override
  State<SafetyNavigatorPage> createState() => _SafetyNavigatorPageState();
}

class _SafetyNavigatorPageState extends State<SafetyNavigatorPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _debugRouting = true;
  String? _debugLastMsg;     // shown in the little overlay
String? _debugEncoded;     
  // shared
  String mode = 'walking'; // walking | driving | cycling
  int resolution = 9;
  String? cityContext;

  // plan route state
  LatLng _origin = const LatLng(lat: 33.8938, lng: 35.5018);
  LatLng _destination = const LatLng(lat: 33.8886, lng: 35.4955);
  String _originLabel = 'Beirut';
  String _destLabel = 'Downtown';
  PickTarget _planTarget = PickTarget.destination;

  double alpha = 0.6;
  bool alternatives = true;
  bool planBusy = false;
  SafestResponse? planRes;
  String? planErr;

  // exit to safety state
  LatLng _position = const LatLng(lat: 33.8938, lng: 35.5018);
  String _posLabel = 'Beirut';
  bool exitBusy = false;
  ExitResponse? exitRes;
  String? exitErr;
  int maxRings = 4;
  double downThreshold = 5, upThreshold = 7, minJump = 1;
  double? prevScore;
  String? phone, topicArn;

  // live tracking
  StreamSubscription<Position>? _posSub;
  bool liveFollowPlan = false;
  bool liveFollowExit = false;
  bool autoReplan = true;
  final List<gmaps.LatLng> _liveTrail = [];

  // google maps
  gmaps.GoogleMapController? _map;
  Set<gmaps.Marker> _markers = {};
  Set<gmaps.Polyline> _polylines = {};
  PickTarget? _mapTapTarget;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _origin = _clampLB(_origin);
    _destination = _clampLB(_destination);
    _position = _clampLB(_position);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapLocation());
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _tab.dispose();
    super.dispose();
  }
  // distance (meters)
double _distM2(gmaps.LatLng a, gmaps.LatLng b) {
  const R = 6371000.0;
  final dLat = (b.latitude - a.latitude) * (3.141592653589793 / 180);
  final dLon = (b.longitude - a.longitude) * (3.141592653589793 / 180);
  final la1 = a.latitude * (3.141592653589793 / 180);
  final la2 = b.latitude * (3.141592653589793 / 180);
  final x = (sin(dLat / 2) * sin(dLat / 2)) + (cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2));
  return 2 * R * atan2(sqrt(x), sqrt(1 - x));
}

// decode with specified precision
List<gmaps.LatLng> _polyDecode(String enc, {int precision = 5}) {
  int index = 0, lat = 0, lng = 0;
  final out = <gmaps.LatLng>[];
  final factor = precision == 6 ? 1000000 : 100000;
  int next() {
    int res = 0, shift = 0, b;
    do { b = enc.codeUnitAt(index++) - 63; res |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
    return (res & 1) != 0 ? ~(res >> 1) : (res >> 1);
  }
  while (index < enc.length) { lat += next(); lng += next(); out.add(gmaps.LatLng(lat / factor, lng / factor)); }
  return out;
}

// sanity summary for a polyline
String _summarizePts(List<gmaps.LatLng> pts) {
  if (pts.isEmpty) return 'pts=0';
  final swLat = pts.map((p) => p.latitude).reduce(min);
  final neLat = pts.map((p) => p.latitude).reduce(max);
  final swLng = pts.map((p) => p.longitude).reduce(min);
  final neLng = pts.map((p) => p.longitude).reduce(max);
  int outside = pts.where((p) => !_inLebanon(p.latitude, p.longitude)).length;
  double maxJump = 0;
  for (int i = 1; i < pts.length; i++) { maxJump = max(maxJump, _distM2(pts[i-1], pts[i])); }
  return 'pts=${pts.length} bbox=[$swLat,$swLng]→[$neLat,$neLng] outsideLB=$outside maxJump=${maxJump.toStringAsFixed(0)}m';
}

// main logger used below
void _logRouteDebug({required String source, required String? encoded}) {
  if (!_debugRouting) return;
  try {
    final enc = encoded ?? '';
    List<gmaps.LatLng> p5 = enc.isNotEmpty ? _polyDecode(enc, precision: 5) : const [];
    List<gmaps.LatLng> p6 = enc.isNotEmpty ? _polyDecode(enc, precision: 6) : const [];
    final msg = StringBuffer()
      ..writeln('ROUTE DEBUG [$source]')
      ..writeln('encoded.len=${enc.length}')
      ..writeln('p5  -> ${_summarizePts(p5)}')
      ..writeln('p6  -> ${_summarizePts(p6)}');
    debugPrint(msg.toString());
    setState(() {
      _debugLastMsg = msg.toString();
      _debugEncoded = enc;
    });
  } catch (e) {
    debugPrint('ROUTE DEBUG ERROR: $e');
  }
}

  // --- Haversine (meters) ---
double _distM(gmaps.LatLng a, gmaps.LatLng b) {
  const R = 6371000.0;
  final dLat = (b.latitude - a.latitude) * (3.141592653589793 / 180);
  final dLon = (b.longitude - a.longitude) * (3.141592653589793 / 180);
  final la1 = a.latitude * (3.141592653589793 / 180);
  final la2 = b.latitude * (3.141592653589793 / 180);
  final x = (sin(dLat / 2) * sin(dLat / 2)) +
      (cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2));
  return 2 * R * atan2(sqrt(x), sqrt(1 - x));
}

// Decode with configurable precision (1e5 = Google/OSRM polyline5, 1e6 = polyline6/Mapbox/ORS)
List<gmaps.LatLng> _polylineDecode(String encoded, {int precision = 5}) {
  int index = 0, lat = 0, lng = 0;
  final List<gmaps.LatLng> out = [];
  int factor = precision == 6 ? 1000000 : 100000;

  int nextChunk() {
    int result = 0, shift = 0, b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  while (index < encoded.length) {
    lat += nextChunk();
    lng += nextChunk();
    out.add(gmaps.LatLng(lat / factor, lng / factor));
  }
  return out;
}

// Try polyline5 first, then polyline6; pick the one that looks sane for Lebanon
List<gmaps.LatLng> _decodeAnyPolyline(String encoded) {
  List<gmaps.LatLng> p5 = _polylineDecode(encoded, precision: 5);
  List<gmaps.LatLng> p6 = _polylineDecode(encoded, precision: 6);

  bool _plausible(List<gmaps.LatLng> pts) {
    if (pts.length < 2) return false;
    // most points inside Lebanon
    final inside = pts.where((p) => _inLebanon(p.latitude, p.longitude)).length;
    if (inside < (pts.length * 0.6)) return false;
    // no absurd jumps
    int spikes = 0;
    for (int i = 1; i < pts.length; i++) {
      if (_distM(pts[i - 1], pts[i]) > 15000) spikes++; // >15 km between consecutive samples
      if (spikes > 2) return false;
    }
    return true;
  }

  if (_plausible(p5) && !_plausible(p6)) return p5;
  if (_plausible(p6) && !_plausible(p5)) return p6;

  // if both plausible, pick the smoother (smaller average step)
  double _avgStep(List<gmaps.LatLng> pts) {
    double sum = 0;
    for (int i = 1; i < pts.length; i++) sum += _distM(pts[i - 1], pts[i]);
    return sum / (pts.length - 1);
  }
  if (p5.isNotEmpty && p6.isNotEmpty) {
    return _avgStep(p6) < _avgStep(p5) ? p6 : p5;
  }
  return p5.isNotEmpty ? p5 : p6;
}

// Remove outliers that create “to the moon” spikes
List<gmaps.LatLng> _sanitizeTrack(List<gmaps.LatLng> pts) {
  if (pts.length < 2) return pts;
  final List<gmaps.LatLng> out = [];
  gmaps.LatLng? prev;
  for (final p in pts) {
    if (!_inLebanon(p.latitude, p.longitude)) continue;
    if (prev != null && _distM(prev, p) > 20000) { // drop >20 km jumps
      continue;
    }
    out.add(p);
    prev = p;
  }
  return out.length >= 2 ? out : pts;
}

  // Directions (fallback) — returns street-following polyline
  Future<List<gmaps.LatLng>> _directionsPolyline(LatLng a, LatLng b) async {
    if (_GMAPS_KEY.isEmpty) return const [];
    final m = (mode == 'cycling') ? 'bicycling' : (mode == 'walking' ? 'walking' : 'driving');
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${a.lat},${a.lng}'
        '&destination=${b.lat},${b.lng}'
        '&mode=$m'
        '&region=lb'
        '&key=$_GMAPS_KEY',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];
      final json = jsonDecode(res.body);
      final routes = (json['routes'] as List?) ?? const [];
      if (routes.isEmpty) return const [];
      // prefer steps for fidelity
      final List<gmaps.LatLng> allPts = [];
      final legs = (routes[0]['legs'] as List?) ?? const [];
      for (final leg in legs) {
        final steps = (leg['steps'] as List?) ?? const [];
        for (final s in steps) {
          final enc = (s['polyline'] as Map)['points'] as String;
          allPts.addAll(_decodeGooglePolylineToGmaps(enc));
        }
      }
      if (allPts.length >= 2) return allPts;
      // fallback to overview polyline
      final poly = (routes[0]['overview_polyline'] as Map)['points'] as String;
      final overview = (routes[0]['overview_polyline'] as Map?)?['points'] as String?;
_logRouteDebug(source: 'directions.overview', encoded: overview);

      return _decodeGooglePolylineToGmaps(poly);
    } catch (_) {
      return const [];
    }
  }
Future<List<gmaps.LatLng>> _orsDirectionsPolyline(LatLng a, LatLng b) async {
  if (_ORS_KEY.isEmpty) return const [];
  try {
    final uri = Uri.parse('https://api.openrouteservice.org/v2/directions/driving-car/geojson');
    final body = jsonEncode({
      'coordinates': [
        [a.lng, a.lat],  // ORS expects [lon, lat]
        [b.lng, b.lat]
      ]
    });
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': _ORS_KEY,
      },
      body: body,
    ).timeout(const Duration(seconds: 12));

    if (res.statusCode != 200) {
      debugPrint('[ors] status=${res.statusCode} body=${res.body}');
      return const [];
    }

    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final features = (j['features'] as List?) ?? const [];
    if (features.isEmpty) return const [];

    final geometry = (features.first['geometry'] as Map?) ?? const {};
    final coords = (geometry['coordinates'] as List?) ?? const [];

    final out = <gmaps.LatLng>[];
    for (final c in coords) {
      if (c is List && c.length >= 2) {
        final lon = (c[0] as num).toDouble();
        final lat = (c[1] as num).toDouble();
        out.add(gmaps.LatLng(lat, lon));
      }
    }
    return out;
  } catch (e) {
    debugPrint('[ors] error: $e');
    return const [];
  }
}

  Future<void> _bootstrapLocation() async {
    try {
      if (!await _ensureLocPerm()) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
      if (!_inLebanon(pos.latitude, pos.longitude)) return;
      final here = LatLng(lat: pos.latitude, lng: pos.longitude);
      final label = await _reverseLabel(here);
      setState(() {
        _origin = here;
        _position = here;
        _originLabel = 'Live: $label';
        _posLabel = 'Live: $label';
      });
      _panTo(here, zoom: 14);
    } catch (_) {}
  }

  LatLng _clampLB(LatLng p) => LatLng(
        lat: p.lat.clamp(_LEB_MIN_LAT, _LEB_MAX_LAT).toDouble(),
        lng: p.lng.clamp(_LEB_MIN_LNG, _LEB_MAX_LNG).toDouble(),
      );

  // ===== geocoding / location / map helpers =====
  Future<bool> _ensureLocPerm() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
  }

  Future<List<_PlacePred>> _placesAutocomplete(String input) async {
    if (_GMAPS_KEY.isEmpty || input.trim().isEmpty) return const [];
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(input)}&components=country:LB&key=$_GMAPS_KEY',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return const [];
      final j = jsonDecode(res.body);
      final preds = (j['predictions'] as List?) ?? const [];
      return preds.map((p) => _PlacePred(p['description'], p['place_id'])).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<LatLng?> _placeDetails(String placeId) async {
    if (_GMAPS_KEY.isEmpty) return null;
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$placeId&fields=geometry/location,name&key=$_GMAPS_KEY',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body);
      final r = j['result'];
      if (r == null) return null;
      final loc = r['geometry']?['location'];
      if (loc == null) return null;
      final lat = (loc['lat'] as num).toDouble();
      final lng = (loc['lng'] as num).toDouble();
      if (!_inLebanon(lat, lng)) return null;
      return LatLng(lat: lat, lng: lng);
    } catch (_) {
      return null;
    }
  }

  Future<LatLng?> _osmGeocodeLB(String q) async {
    try {
      final uri = Uri.parse(
        '$_OSM_SEARCH?q=${Uri.encodeComponent(q)}'
        '&format=json&limit=5&countrycodes=lb'
        '&viewbox=$_LEB_MIN_LNG,$_LEB_MAX_LAT,$_LEB_MAX_LNG,$_LEB_MIN_LAT&bounded=1',
      );
      final res = await http.get(uri, headers: {'User-Agent': 'safesteps-app'}).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(res.body) as List;
      if (list.isEmpty) return null;
      final first = list.first;
      final lat = double.parse(first['lat']);
      final lng = double.parse(first['lon']);
      if (!_inLebanon(lat, lng)) return null;
      return LatLng(lat: lat, lng: lng);
    } catch (_) {
      return null;
    }
  }

  Future<String> _osmReverse(LatLng p) async {
    try {
      final uri = Uri.parse(
        '$_OSM_REVERSE?lat=${p.lat}&lon=${p.lng}&format=jsonv2'
        '&zoom=17&addressdetails=1',
      );
      final res = await http.get(uri, headers: {'User-Agent': 'safesteps-app'}).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return 'Pinned on map';
      final j = jsonDecode(res.body);
      return (j['display_name'] as String?) ?? 'Pinned on map';
    } catch (_) {
      return 'Pinned on map';
    }
  }

  Future<LatLng?> _geocode(String q) async {
    if (_GMAPS_KEY.isNotEmpty) {
      final preds = await _placesAutocomplete(q);
      if (preds.isNotEmpty) {
        final p = await _placeDetails(preds.first.placeId);
        if (p != null) return p;
      }
      try {
        final uri = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json'
          '?address=${Uri.encodeComponent(q)}&components=country:LB&key=$_GMAPS_KEY',
        );
        final res = await http.get(uri).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body);
          final results = (json['results'] as List?) ?? const [];
          if (results.isNotEmpty) {
            final loc = results[0]['geometry']['location'];
            final lat = (loc['lat'] as num).toDouble();
            final lng = (loc['lng'] as num).toDouble();
            if (_inLebanon(lat, lng)) return LatLng(lat: lat, lng: lng);
          }
        }
      } catch (_) {}
    }

    if (kIsWeb) {
      return _osmGeocodeLB(q);
    }

    try {
      final list = await gc.locationFromAddress('$q, Lebanon', localeIdentifier: 'en_LB');
      if (list.isEmpty) return null;
      final loc = list.first;
      if (!_inLebanon(loc.latitude, loc.longitude)) return null;
      return LatLng(lat: loc.latitude, lng: loc.longitude);
    } catch (_) { return null; }
  }

  Future<String> _reverseLabel(LatLng p) async {
    if (_GMAPS_KEY.isNotEmpty) {
      try {
        final uri = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json'
          '?latlng=${p.lat},${p.lng}'
          '&result_type=street_address|route|sublocality|locality'
          '&key=$_GMAPS_KEY',
        );
        final res = await http.get(uri).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body);
          final results = (json['results'] as List?) ?? const [];
          if (results.isNotEmpty) return results[0]['formatted_address'] as String;
        }
      } catch (_) {}
    }
    if (kIsWeb) return _osmReverse(p);
    try {
      final placemarks = await gc.placemarkFromCoordinates(p.lat, p.lng, localeIdentifier: 'en_LB');
      if (placemarks.isEmpty) return 'Pinned on map';
      final pm = placemarks.first;
      final parts = [pm.name, pm.street, pm.subLocality, pm.locality]
          .where((e) => (e ?? '').trim().isNotEmpty)
          .map((e) => e!.trim()).toList();
      return parts.isEmpty ? 'Pinned on map' : parts.first;
    } catch (_) { return 'Pinned on map'; }
  }

  void _panTo(LatLng p, {double zoom = 14}) {
    if (_map == null || _usePlaceholder) return;
    if (!_inLebanon(p.lat, p.lng)) return;
    _map!.animateCamera(gmaps.CameraUpdate.newLatLngZoom(gmaps.LatLng(p.lat, p.lng), zoom));
  }

  // ===== backend calls =====
  Future<void> _plan() async {
    setState(() { planBusy = true; planErr = null; planRes = null; });
    try {
      final res = await postSafestRoute(RouteRequest(
        origin: _origin,
        destination: _destination,
        city: (cityContext?.trim().isEmpty ?? true) ? null : cityContext,
        resolution: resolution,
        alternatives: alternatives,
        mode: mode,
        alpha: alpha,
      ));
      setState(() => planRes = res);
      if (!_usePlaceholder) await _drawPlanOnMap(res);
    } catch (e) {
      setState(() { planErr = e.toString(); _polylines = {}; _markers = {}; });
    } finally {
      setState(() => planBusy = false);
    }
  }

  Future<void> _exitToSafety() async {
    setState(() { exitBusy = true; exitErr = null; exitRes = null; });
    try {
      final res = await postExitToSafety(ExitToSafetyRequest(
        position: _position,
        city: (cityContext?.trim().isEmpty ?? true) ? null : cityContext,
        resolution: resolution,
        maxRings: maxRings,
        mode: mode,
        prevScore: prevScore,
        upThreshold: upThreshold,
        downThreshold: downThreshold,
        minJump: minJump,
        phone: phone,
        topicArn: topicArn,
      ));
      setState(() => exitRes = res);
      if (res is ExitSuccess && !_usePlaceholder) await _drawExitOnMap(res);
      if (res is ExitNotFound) { _polylines = {}; _markers = {}; }
    } catch (e) {
      setState(() { exitErr = e.toString(); _polylines = {}; _markers = {}; });
    } finally {
      setState(() => exitBusy = false);
    }
  }

  // ===== live tracking =====
  LocationSettings _liveSettingsForMode() {
    switch (mode) {
      case 'walking': return const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 4);
      case 'cycling': return const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 6);
      case 'driving':
      default:        return const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 12);
    }
  }

  Future<void> _ensureLiveStream() async {
    if (_posSub != null) return;
    if (!await _ensureLocPerm()) return;

    _posSub = Geolocator.getPositionStream(locationSettings: _liveSettingsForMode())
        .listen((pos) async {
      if (!_inLebanon(pos.latitude, pos.longitude)) return;
      final live = LatLng(lat: pos.latitude, lng: pos.longitude);

      if (liveFollowPlan) { _origin = live; _originLabel = 'Live location'; }
      if (liveFollowExit)  { _position = live; _posLabel = 'Live location'; }

      final p = gmaps.LatLng(pos.latitude, pos.longitude);
      _liveTrail.add(p);
      if (_liveTrail.length > 1) {
        _polylines.removeWhere((pl) => pl.polylineId.value == 'live');
        _polylines.add(gmaps.Polyline(
          polylineId: const gmaps.PolylineId('live'),
          points: List.of(_liveTrail),
          width: 4,
          color: Colors.indigo,
          geodesic: true,
        ));
      }

      _panTo(live);
      if (autoReplan && !_usePlaceholder) {
        if (_tab.index == 0 && liveFollowPlan && !planBusy) await _plan();
        if (_tab.index == 1 && liveFollowExit && !exitBusy) await _exitToSafety();
      }
      if (mounted) setState(() {});
    });
  }

  void _stopLiveIfNoneActive() {
    if (!liveFollowPlan && !liveFollowExit) {
      _posSub?.cancel();
      _posSub = null;
      _polylines.removeWhere((pl) => pl.polylineId.value == 'live');
    }
  }

  // ===== draw helpers (Google-style cased polylines) =====

  List<gmaps.LatLng> _decodeGooglePolylineToGmaps(String encoded) {
    int index = 0, lat = 0, lng = 0;
    final out = <gmaps.LatLng>[];

    int nextChunk() {
      int result = 0, shift = 0, b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    }

    while (index < encoded.length) {
      lat += nextChunk();
      lng += nextChunk();
      out.add(gmaps.LatLng(lat / 1e5, lng / 1e5));
    }
    return out;
  }

  void _addChosenPolyline(List<gmaps.LatLng> gpts, String id) {
    if (gpts.isEmpty) return;
    _polylines.addAll([
      gmaps.Polyline(
        polylineId: gmaps.PolylineId('${id}_shadow'),
        points: gpts,
        geodesic: true,
        width: 20,
        color: Colors.black.withOpacity(0.15),
        zIndex: 10,
        startCap: gmaps.Cap.roundCap,
        endCap: gmaps.Cap.roundCap,
        jointType: gmaps.JointType.round,
      ),
      gmaps.Polyline(
        polylineId: gmaps.PolylineId('${id}_halo'),
        points: gpts,
        geodesic: true,
        width: 14,
        color: Colors.white,
        zIndex: 20,
        startCap: gmaps.Cap.roundCap,
        endCap: gmaps.Cap.roundCap,
        jointType: gmaps.JointType.round,
      ),
      gmaps.Polyline(
        polylineId: gmaps.PolylineId('${id}_core'),
        points: gpts,
        geodesic: true,
        width: 8,
        color: const Color(0xFF1A73E8),
        zIndex: 30,
        startCap: gmaps.Cap.roundCap,
        endCap: gmaps.Cap.roundCap,
        jointType: gmaps.JointType.round,
      ),
    ]);
  }

 Future<void> _drawPlanOnMap(SafestResponse res) async {
  final chosen = res.chosen;

  // Keep this to inspect backend strings in the overlay, but we won't use it for drawing.
  _logRouteDebug(source: 'plan.chosen', encoded: chosen.encodedPolyline);

  _polylines = {};
  _markers = {
    gmaps.Marker(
      markerId: const gmaps.MarkerId('origin'),
      position: gmaps.LatLng(_origin.lat, _origin.lng),
      infoWindow: gmaps.InfoWindow(title: 'Origin', snippet: _originLabel),
    ),
    gmaps.Marker(
      markerId: const gmaps.MarkerId('dest'),
      position: gmaps.LatLng(_destination.lat, _destination.lng),
      infoWindow: gmaps.InfoWindow(title: 'Destination', snippet: _destLabel),
    ),
  };

  bool drew = false;

  // 1) ✅ Prefer server points (if your backend provides them)
  if (chosen.polylinePoints != null && chosen.polylinePoints!.isNotEmpty) {
    var g = chosen.polylinePoints!
        .map((p) => gmaps.LatLng(p.lat, p.lng))
        .toList();
    g = _sanitizeTrack(g);
    if (g.length >= 2) {
      _addChosenPolyline(g, 'chosen_pts');
      _map?.animateCamera(gmaps.CameraUpdate.newLatLngBounds(_bounds(g), 40));
      drew = true;
    }
  }

  // 2) Fallback: Google Directions between origin/destination
  // ORS fallback (especially for Web where Google REST gets CORS-blocked)
if (!drew) {
  var gpts = await _orsDirectionsPolyline(_origin, _destination);
  gpts = _sanitizeTrack(gpts);
  if (gpts.length >= 2) {
    _addChosenPolyline(gpts, 'ors_fallback');
    _map?.animateCamera(gmaps.CameraUpdate.newLatLngBounds(_bounds(gpts), 40));
    drew = true;
  }
}


  // 3) Last resort: straight dashed line so the user sees something
  if (!drew) {
    final a = gmaps.LatLng(_origin.lat, _origin.lng);
    final b = gmaps.LatLng(_destination.lat, _destination.lng);
    _polylines.add(gmaps.Polyline(
      polylineId: const gmaps.PolylineId('straight_fallback'),
      points: [a, b],
      width: 3,
      color: Colors.black54,
      geodesic: true,
      patterns: <gmaps.PatternItem>[gmaps.PatternItem.dash(20), gmaps.PatternItem.gap(10)],
    ));
    _map?.animateCamera(gmaps.CameraUpdate.newLatLngBounds(_bounds([a, b]), 60));
  }

  setState(() {});
}



 Future<void> _drawExitOnMap(ExitSuccess res) async {
  final chosen = res.route.chosen;

  // Still log for debugging, but we won't decode this for drawing.
  _logRouteDebug(source: 'exit.chosen', encoded: chosen.encodedPolyline);

  _polylines = {};
  _markers = {
    gmaps.Marker(
      markerId: const gmaps.MarkerId('pos'),
      position: gmaps.LatLng(_position.lat, _position.lng),
      infoWindow: const gmaps.InfoWindow(title: 'Position'),
    ),
    gmaps.Marker(
      markerId: const gmaps.MarkerId('safe'),
      position: gmaps.LatLng(res.safeTarget.lat, res.safeTarget.lng),
      infoWindow: const gmaps.InfoWindow(title: 'Nearest safe'),
    ),
  };

  bool drew = false;

  // 1) ✅ Prefer server points
  if (chosen.polylinePoints != null && chosen.polylinePoints!.isNotEmpty) {
    var g = chosen.polylinePoints!
        .map((p) => gmaps.LatLng(p.lat, p.lng))
        .toList();
    g = _sanitizeTrack(g);
    if (g.length >= 2) {
      _addChosenPolyline(g, 'exit_pts');
      _map?.animateCamera(gmaps.CameraUpdate.newLatLngBounds(_bounds(g), 40));
      drew = true;
    }
  }

  // 2) Fallback: Directions from current position to safe target
  // ORS fallback (especially for Web)
if (!drew) {
  var gpts = await _orsDirectionsPolyline(
    _position,
    LatLng(lat: res.safeTarget.lat, lng: res.safeTarget.lng),
  );
  gpts = _sanitizeTrack(gpts);
  if (gpts.length >= 2) {
    _addChosenPolyline(gpts, 'ors_fallback');
    _map?.animateCamera(gmaps.CameraUpdate.newLatLngBounds(_bounds(gpts), 40));
    drew = true;
  }
}


  // 3) Last resort: straight dashed
  if (!drew) {
    final a = gmaps.LatLng(_position.lat, _position.lng);
    final b = gmaps.LatLng(res.safeTarget.lat, res.safeTarget.lng);
    _polylines.add(gmaps.Polyline(
      polylineId: const gmaps.PolylineId('straight_exit'),
      points: [a, b],
      width: 3,
      color: Colors.black54,
      geodesic: true,
      patterns: <gmaps.PatternItem>[gmaps.PatternItem.dash(20), gmaps.PatternItem.gap(10)],
    ));
    _map?.animateCamera(gmaps.CameraUpdate.newLatLngBounds(_bounds([a, b]), 60));
  }

  setState(() {});
}



  gmaps.LatLngBounds _bounds(List<gmaps.LatLng> pts) {
    final inside = pts.where((p) => _inLebanon(p.latitude, p.longitude)).toList();
    if (inside.isEmpty) return _LB_BOUNDS;

    double minLat = inside.first.latitude, maxLat = inside.first.latitude;
    double minLng = inside.first.longitude, maxLng = inside.first.longitude;
    for (final p in inside) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final sw = gmaps.LatLng(
      min(max(minLat, _LEB_MIN_LAT), _LEB_MAX_LAT),
      min(max(minLng, _LEB_MIN_LNG), _LEB_MAX_LNG),
    );
    final ne = gmaps.LatLng(
      max(min(maxLat, _LEB_MAX_LAT), _LEB_MIN_LAT),
      max(min(maxLng, _LEB_MAX_LNG), _LEB_MIN_LNG),
    );
    return gmaps.LatLngBounds(southwest: sw, northeast: ne);
  }

  // ===== map widget =====
  bool get _usePlaceholder => kIsWeb && !_WEB_MAPS_ENABLED;

  void _onSafetyPressed() {
    if (_tab.index == 0) {
      _openSafeSuggestionsAround(_origin);
    } else {
      _openSafeSuggestionsAround(_position);
    }
  }

  Widget _mapWidget() {
  // Placeholder for web when maps disabled
  if (_usePlaceholder) {
    return Container(
      height: 260,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Map disabled on Web.\nAdd a Google Maps JS API key to web/index.html '
          'and run with --dart-define=WEB_MAPS_ENABLED=true to enable.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // Real Google Map
  final mapChild = gmaps.GoogleMap(
    mapType: gmaps.MapType.terrain,
    initialCameraPosition: gmaps.CameraPosition(
      target: gmaps.LatLng(_origin.lat, _origin.lng),
      zoom: 12,
    ),
    myLocationButtonEnabled: false,
    myLocationEnabled: false,
    zoomControlsEnabled: true,
    cameraTargetBounds: gmaps.CameraTargetBounds(_LB_BOUNDS),
    minMaxZoomPreference: const gmaps.MinMaxZoomPreference(8, 19),
    markers: _markers,
    polylines: _polylines,
    gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
      Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
    },
    onMapCreated: (c) => _map = c,
    onTap: (p) async {
      if (_mapTapTarget == null) return;
      if (!_inLebanon(p.latitude, p.longitude)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please pick inside Lebanon')),
          );
        }
        return;
      }
      final clamped = _clampLB(LatLng(lat: p.latitude, lng: p.longitude));
      final label = await _reverseLabel(clamped);

      switch (_mapTapTarget!) {
        case PickTarget.origin:
          _origin = clamped; _originLabel = label; break;
        case PickTarget.destination:
          _destination = clamped; _destLabel = label; break;
        case PickTarget.position:
          _position = clamped; _posLabel = label; break;
      }
      setState(() => _mapTapTarget = null);
    },
  );

  return SizedBox(
    height: 260,
    child: Stack(
      children: [
        Positioned.fill(child: mapChild),

        // Safety FAB near the "-" zoom
        Positioned(
          right: 16,
          bottom: 90,
          child: Tooltip(
            message: 'Safety',
            child: FloatingActionButton.small(
              heroTag: 'safetyBtn',
              onPressed: _onSafetyPressed,
              child: const Icon(Icons.safety_check),
            ),
          ),
        ),

        // Debug panel (only when enabled)
        if (_debugRouting && _debugLastMsg != null)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Card(
              color: Colors.black.withOpacity(0.75),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Route debug',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.copy, size: 16, color: Colors.white70),
                          tooltip: 'Copy encoded polyline',
                          onPressed: _debugEncoded == null
                              ? null
                              : () => Clipboard.setData(
                                    ClipboardData(text: _debugEncoded!),
                                  ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 16, color: Colors.white70),
                          onPressed: () => setState(() => _debugLastMsg = null),
                        ),
                      ],
                    ),
                    Text(
                      _debugLastMsg!,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}



  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Safety Navigator'),
          bottom: const TabBar(tabs: [Tab(text: 'Plan Route'), Tab(text: 'Exit to Safety')]),
        ),
        body: Column(
          children: [
            _mapWidget(),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(children: [
                _planTab(),
                _exitTab(),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- PLAN TAB ----------
  Widget _planTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<PickTarget>(
            segments: const [
              ButtonSegment(value: PickTarget.origin, icon: Icon(Icons.flag), label: Text('Origin')),
              ButtonSegment(value: PickTarget.destination, icon: Icon(Icons.place), label: Text('Destination')),
            ],
            selected: {_planTarget},
            onSelectionChanged: (s) => setState(() => _planTarget = s.first),
          ),
          const SizedBox(height: 10),

          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Search city / place'),
                onPressed: () => _openSearchSheet(_planTarget),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.my_location),
                label: const Text('Use my location'),
                onPressed: () async {
                  try {
                    if (!await _ensureLocPerm()) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Location permission denied')),
                      );
                      return;
                    }
                    final p = await Geolocator.getCurrentPosition(
                      desiredAccuracy: LocationAccuracy.bestForNavigation,
                    );
                    if (!_inLebanon(p.latitude, p.longitude)) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Your location appears outside Lebanon')),
                      );
                      return;
                    }
                    final here = LatLng(lat: p.latitude, lng: p.longitude);
                    final label = await _reverseLabel(here);
                    if (_planTarget == PickTarget.origin) { _origin = here; _originLabel = label; }
                    else { _destination = here; _destLabel = label; }
                    _panTo(here);
                    setState(() {});
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Location error: $e')),
                    );
                  }
                },
              ),
              FilledButton.icon(
                icon: Icon(_mapTapTarget == null ? Icons.add_location_alt_outlined : Icons.touch_app),
                label: Text(_mapTapTarget == null ? 'Pick on map' : 'Tap map…'),
                onPressed: _usePlaceholder ? null : () {
                  setState(() => _mapTapTarget = _planTarget);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Tap the map to set the location')),
                  );
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Swap'),
                onPressed: () {
                  final o = _origin; final ol = _originLabel;
                  _origin = _destination; _originLabel = _destLabel;
                  _destination = o; _destLabel = ol;
                  _panTo(_origin);
                  setState(() {});
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.safety_check),
                label: const Text('Suggest safe destination'),
                onPressed: () => _openSafeSuggestionsAround(_origin),
              ),
            ],
          ),

          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: _quick.map<Widget>((c) => ActionChip(
              label: Text(c.name),
              onPressed: () async {
                final p = _clampLB(LatLng(lat: c.lat, lng: c.lng));
                final label = await _reverseLabel(p);
                if (_planTarget == PickTarget.origin) { _origin = p; _originLabel = label; }
                else { _destination = p; _destLabel = label; }
                _panTo(p);
                setState(() {});
              },
            )).toList(),
          ),

          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.route),
              title: Text('$_originLabel → $_destLabel'),
              subtitle: Text('Mode: $mode • Safety bias: ${alpha.toStringAsFixed(2)} • Res: $resolution'),
              trailing: IconButton(
                tooltip: 'Use safest nearby as destination',
                icon: const Icon(Icons.safety_check),
                onPressed: () => _openSafeSuggestionsAround(_origin),
              ),
            ),
          ),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    value: mode,
                    decoration: const InputDecoration(labelText: 'Mode'),
                    items: const [
                      DropdownMenuItem(value: 'walking', child: Text('Walking')),
                      DropdownMenuItem(value: 'driving', child: Text('Driving')),
                      DropdownMenuItem(value: 'cycling', child: Text('Cycling')),
                    ],
                    onChanged: (v) async {
                      setState(() => mode = v ?? 'walking');
                      if (liveFollowPlan || liveFollowExit) {
                        _posSub?.cancel(); _posSub = null;
                        await _ensureLiveStream();
                      }
                    },
                  ),
                  SwitchListTile(
                    value: alternatives,
                    onChanged: (v) => setState(() => alternatives = v),
                    title: const Text('Show alternative routes'),
                  ),
                  Text('Safety ↔ Speed (alpha: ${alpha.toStringAsFixed(2)})'),
                  Slider(min: 0, max: 1, divisions: 100, value: alpha, onChanged: (v) => setState(() => alpha = v)),

                  SwitchListTile(
                    value: liveFollowPlan,
                    onChanged: (v) async {
                      setState(() => liveFollowPlan = v);
                      if (v) { await _ensureLiveStream(); } else { _stopLiveIfNoneActive(); }
                    },
                    title: const Text('Live track origin'),
                  ),

                  const SizedBox(height: 6),
                  ExpansionTile(
                    title: const Text('Advanced (optional)'),
                    children: [
                      TextFormField(
                        initialValue: '$resolution',
                        decoration: const InputDecoration(labelText: 'H3 resolution (1–15)'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: false),
                        onChanged: (s) => setState(() => resolution = int.tryParse(s) ?? resolution),
                      ),
                      TextFormField(
                        initialValue: cityContext ?? '',
                        decoration: const InputDecoration(labelText: 'City context (optional)'),
                        onChanged: (s) => setState(() => cityContext = s),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),

                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: planBusy ? null : _plan,
                    icon: const Icon(Icons.directions),
                    label: Text(planBusy ? 'Planning…' : 'Plan route'),
                  ),
                ],
              ),
            ),
          ),
          if (planErr != null) Padding(padding: const EdgeInsets.all(8), child: Text(planErr!, style: const TextStyle(color: Colors.red))),
          if (planRes != null) ...[
            _chosenCard(planRes!.chosen),
            _candidatesTable(planRes!.candidates),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ---------- EXIT TAB ----------
  Widget _exitTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Search city / place'),
                onPressed: () => _openSearchSheet(PickTarget.position),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.my_location),
                label: const Text('Use my location'),
                onPressed: () async {
                  try {
                    if (!await _ensureLocPerm()) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Location permission denied')),
                      );
                      return;
                    }
                    final p = await Geolocator.getCurrentPosition(
                      desiredAccuracy: LocationAccuracy.bestForNavigation,
                    );
                    if (!_inLebanon(p.latitude, p.longitude)) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Your location appears outside Lebanon')),
                      );
                      return;
                    }
                    _position = LatLng(lat: p.latitude, lng: p.longitude);
                    _posLabel = await _reverseLabel(_position);
                    _panTo(_position);
                    setState(() {});
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Location error: $e')),
                    );
                  }
                },
              ),
              FilledButton.icon(
                icon: Icon(_mapTapTarget == PickTarget.position ? Icons.touch_app : Icons.add_location_alt_outlined),
                label: Text(_mapTapTarget == PickTarget.position ? 'Tap map…' : 'Pick on map'),
                onPressed: _usePlaceholder ? null : () {
                  setState(() => _mapTapTarget = PickTarget.position);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Tap the map to set the location')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: _quick.map<Widget>((c) => ActionChip(
              label: Text(c.name),
              onPressed: () async {
                final p = _clampLB(LatLng(lat: c.lat, lng: c.lng));
                _position = p; _posLabel = await _reverseLabel(p);
                _panTo(p); setState(() {});
              },
            )).toList(),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.place),
              title: Text('Position: $_posLabel'),
              subtitle: const Text('Find a safe place nearby and route to it'),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    value: mode,
                    decoration: const InputDecoration(labelText: 'Mode'),
                    items: const [
                      DropdownMenuItem(value: 'walking', child: Text('Walking')),
                      DropdownMenuItem(value: 'driving', child: Text('Driving')),
                      DropdownMenuItem(value: 'cycling', child: Text('Cycling')),
                    ],
                    onChanged: (v) async {
                      setState(() => mode = v ?? 'walking');
                      if (liveFollowPlan || liveFollowExit) {
                        _posSub?.cancel(); _posSub = null;
                        await _ensureLiveStream();
                      }
                    },
                  ),

                  SwitchListTile(
                    value: liveFollowExit,
                    onChanged: (v) async {
                      setState(() => liveFollowExit = v);
                      if (v) { await _ensureLiveStream(); } else { _stopLiveIfNoneActive(); }
                    },
                    title: const Text('Live track position'),
                  ),

                  const SizedBox(height: 6),
                  ExpansionTile(
                    title: const Text('Advanced (optional)'),
                    children: [
                      Row(children: [
                        Expanded(child: _smallNum('Max rings', maxRings.toString(), (s) => setState(() => maxRings = int.tryParse(s) ?? maxRings))),
                        const SizedBox(width: 8),
                        Expanded(child: _smallNum('Down threshold', downThreshold.toString(), (s) => setState(() => downThreshold = double.tryParse(s) ?? downThreshold))),
                      ]),
                      Row(children: [
                        Expanded(child: _smallNum('Up threshold', upThreshold.toString(), (s) => setState(() => upThreshold = double.tryParse(s) ?? upThreshold))),
                        const SizedBox(width: 8),
                        Expanded(child: _smallNum('Min jump', minJump.toString(), (s) => setState(() => minJump = double.tryParse(s) ?? minJump))),
                      ]),
                      _smallNum('Prev score (optional)', prevScore?.toString() ?? '', (s) => setState(() => prevScore = s.isEmpty ? null : double.tryParse(s))),
                      _smallText('City context (optional)', cityContext ?? '', (s) => setState(() => cityContext = s)),
                      _smallText('Phone (optional +E.164)', phone ?? '', (s) => setState(() => phone = s)),
                      _smallText('SNS Topic ARN (optional)', topicArn ?? '', (s) => setState(() => topicArn = s)),
                      const SizedBox(height: 8),
                    ],
                  ),

                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _openSafeSuggestionsAround(_position),
                    icon: const Icon(Icons.safety_check),
                    label: const Text('Find safest place & route'),
                  ),
                ],
              ),
            ),
          ),
          if (exitErr != null) Padding(padding: const EdgeInsets.all(8), child: Text(exitErr!, style: const TextStyle(color: Colors.red))),
          if (exitRes is ExitSuccess) _exitSuccessCard(exitRes as ExitSuccess),
          if (exitRes is ExitNotFound) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text((exitRes as ExitNotFound).detail))),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ---------- small UI helpers ----------
  Widget _smallNum(String label, String initial, void Function(String) onChanged) => TextFormField(
        initialValue: initial,
        decoration: InputDecoration(labelText: label),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: onChanged,
      );

  Widget _smallText(String label, String initial, void Function(String) onChanged) => TextFormField(
        initialValue: initial,
        decoration: InputDecoration(labelText: label),
        onChanged: onChanged,
      );

  Widget _chosenCard(Candidate c) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Chosen route', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Duration: ${fmtDuration(c.durationSec)}'),
            Text('Distance (m): ${c.distanceM}'),
            Text('Avg severity: ${c.score.avgSeverity.toStringAsFixed(2)}'),
            Text('Max severity: ${c.score.maxSeverity.toStringAsFixed(2)}'),
            Text('Samples: ${c.score.samples}'),
          ]),
        ),
      );

  Widget _candidatesTable(List<Candidate> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Candidates', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
              4: FlexColumnWidth(1),
              5: FlexColumnWidth(1)
            },
            border: const TableBorder(horizontalInside: BorderSide(color: Colors.black12)),
            children: [
              _row(['Summary', 'Duration', 'Dist (m)', 'Avg', 'Max', 'Samples'], header: true),
              ...items.map((c) => _row([
                    c.summary,
                    fmtDuration(c.durationSec),
                    '${c.distanceM}',
                    c.score.avgSeverity.toStringAsFixed(2),
                    c.score.maxSeverity.toStringAsFixed(2),
                    '${c.score.samples}',
                  ])),
            ],
          ),
        ]),
      ),
    );
  }

  TableRow _row(List<String> cols, {bool header = false}) => TableRow(
        children: cols
            .map((t) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Text(t, style: header ? const TextStyle(fontWeight: FontWeight.bold) : null),
                ))
            .toList(),
      );

  Widget _exitSuccessCard(ExitSuccess res) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Safe target', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Hex: ${res.safeHex}'),
            Text('Chosen route: ${fmtDuration(res.route.chosen.durationSec)} • ${res.route.chosen.distanceM} m'),
            Text('Avg severity: ${res.route.chosen.score.avgSeverity.toStringAsFixed(2)}  '
                'Max: ${res.route.chosen.score.maxSeverity.toStringAsFixed(2)}  '
                'Samples: ${res.route.chosen.score.samples}'),
            if (res.snsMessageId != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('SNS Message ID: ${res.snsMessageId}', style: const TextStyle(color: Colors.green))),
            if (res.snsError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('SNS Error: ${res.snsError}', style: const TextStyle(color: Colors.red))),
          ]),
        ),
      );

  // ===== search sheet =====
  Future<void> _openSearchSheet(PickTarget target) async {
    final controller = TextEditingController();
    List<_PlacePred> preds = const [];

    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setModal) => Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Search a place (Lebanon only)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'e.g. Hamra Bliss, AUBMC, Tripoli…',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (s) async {
                  if (_GMAPS_KEY.isEmpty) { setModal(() => preds = const []); return; }
                  final r = await _placesAutocomplete(s.trim());
                  setModal(() => preds = r);
                },
                onSubmitted: (_) => Navigator.of(context).pop(controller.text.trim()),
              ),
              const SizedBox(height: 8),
              ...preds.take(8).map((p) => ListTile(
                dense: true,
                leading: const Icon(Icons.place_outlined),
                title: Text(p.desc, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.of(context).pop('place:${p.placeId}|${p.desc}'),
              )),
              if (preds.isEmpty)
                FilledButton.icon(
                  icon: const Icon(Icons.search),
                  label: const Text('Search'),
                  onPressed: () => Navigator.of(context).pop(controller.text.trim()),
                ),
            ],
          ),
        ),
      ),
    );

    final q = (res ?? '').trim();
    if (q.isEmpty) return;

    LatLng? p;
    String label;
    if (q.startsWith('place:')) {
      final parts = q.substring(6).split('|');
      final placeId = parts.first;
      label = parts.length > 1 ? parts[1] : 'Pinned';
      p = await _placeDetails(placeId);
    } else {
      p = await _geocode(q);
      label = q;
    }
    if (p == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No result in Lebanon for "$q"')));
      return;
    }

    label = await _reverseLabel(p);
    switch (target) {
      case PickTarget.origin:      _origin = p; _originLabel = label; break;
      case PickTarget.destination: _destination = p; _destLabel = label; break;
      case PickTarget.position:    _position = p; _posLabel = label; break;
    }
    _panTo(p);
    if (mounted) setState(() {});
  }

  // ===== safe suggestions =====
  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * (3.141592653589793 / 180);
    final dLon = (lon2 - lon1) * (3.141592653589793 / 180);
    final a = sin(dLat/2) * sin(dLat/2) +
              cos(lat1*(3.141592653589793/180)) *
              cos(lat2*(3.141592653589793/180)) *
              sin(dLon/2) * sin(dLon/2);
    final c = 2 * atan2(sqrt(a), sqrt(1-a));
    return R * c;
  }

  Future<List<_Poi>> _safePOIs(LatLng base) async {
    if (_GMAPS_KEY.isNotEmpty) {
      final types = <String>['police','hospital','university','shopping_mall','embassy','fire_station'];
      final Map<String, _Poi> seen = {};
      for (final t in types) {
        try {
          final uri = Uri.parse(
            'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
            '?location=${base.lat},${base.lng}&radius=5000&type=$t&key=$_GMAPS_KEY',
          );
          final res = await http.get(uri).timeout(const Duration(seconds: 10));
          if (res.statusCode != 200) continue;
          final json = jsonDecode(res.body);
          final results = (json['results'] as List?) ?? const [];
          for (final r in results) {
            final pid = r['place_id'] as String?;
            final name = (r['name'] as String?) ?? t;
            final loc = r['geometry']?['location'];
            if (loc == null) continue;
            final lat = (loc['lat'] as num).toDouble();
            final lng = (loc['lng'] as num).toDouble();
            if (!_inLebanon(lat, lng)) continue;
            final d = _haversine(base.lat, base.lng, lat, lng);
            final addr = (r['vicinity'] as String?) ?? '';
            final key = pid ?? '$lat,$lng';
            if (!seen.containsKey(key) || d < seen[key]!.distanceM) {
              seen[key] = _Poi(
                name: name,
                placeId: pid,
                loc: LatLng(lat: lat, lng: lng),
                secondary: addr.isEmpty ? t : addr,
                distanceM: d,
              );
            }
          }
        } catch (_) {}
      }
      final list = seen.values.toList()..sort((a, b) => a.distanceM.compareTo(b.distanceM));
      return list.take(12).toList();
    }

    return [
      _Poi(
        name: 'Nearest safe (suggested)',
        placeId: null,
        loc: base,
        secondary: 'Your current area',
        distanceM: 0,
      )
    ];
  }

  Future<void> _openSafeSuggestionsAround(LatLng base) async {
    final ctx = context;
    final items = await _safePOIs(base);
    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('No nearby suggestions')));
      return;
    }

    final chosen = await showModalBottomSheet<_Poi>(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        maxChildSize: 0.9,
        builder: (_, controller) => Column(
          children: [
            const SizedBox(height: 8),
            const Text('Suggested safe places', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final p = items[i];
                  return ListTile(
                    leading: const Icon(Icons.shield_outlined),
                    title: Text(p.name),
                    subtitle: Text('${p.secondary} • ${(p.distanceM/1000).toStringAsFixed(2)} km'),
                    onTap: () => Navigator.of(ctx).pop(p),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (chosen == null) return;
    _destination = chosen.loc;
    _destLabel = chosen.name;
    setState(() {});
    await _plan();
  }
}
