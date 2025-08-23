// lib/screens/map_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/hex_zone_model.dart';
import '../services/hive_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  Position? _currentPosition;
  StreamSubscription<Position>? _posSub;

  // All zones from Hive (do not render all at once)
  List<HexZone> _allZones = [];

  // Only polygons inside the viewport are rendered
  List<Polygon> _visiblePolygons = [];

  final List<Marker> _markers = [];

  bool _preparing = false; // first-run warmup overlay
  Timer? _periodicCityRefresh;

  // Debounce map movement updates so we don’t thrash
  Timer? _viewDebounce;

  @override
  void initState() {
    super.initState();
    _initFlow();
  }

  @override
  void dispose() {
    _periodicCityRefresh?.cancel();
    _posSub?.cancel();
    _viewDebounce?.cancel();
    super.dispose();
  }

  // -------------------- Init flow --------------------
  Future<void> _initFlow() async {
    await HiveService.initHive();

    // FIRST RUN ONLY: block on warmup so we save all polygons once
    if (!HiveService.isWarmupDone) {
      setState(() => _preparing = true);
      try {
        await HiveService.warmupAllLebanon();
      } finally {
        if (mounted) setState(() => _preparing = false);
      }
    }

    // Load everything from Hive (fast)
    _allZones = HiveService.loadZones();

    // Compute initial visible set after layout
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateVisiblePolys());

    // Get location & quick per-city refresh (updates colors, not boundaries)
    await _acquireLocationOnceAndRefreshCity();

    // Subscribe to location updates (move red dot)
    _subscribeToLocation();

    // Periodic city refresh (lightweight; won’t redraw all)
    _periodicCityRefresh =
        Timer.periodic(const Duration(minutes: 5), (_) async {
      if (_currentPosition == null) return;
      await HiveService.refreshCityByLatLng(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
      // Reload zones (colors may have changed)
      _allZones = HiveService.loadZones();
      _updateVisiblePolys(); // recompute for current bounds
    });
  }

  // -------------------- Location --------------------
  Future<void> _acquireLocationOnceAndRefreshCity() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _currentPosition = pos;

      // Refresh just this city; boundaries should already exist from warmup
      await HiveService.refreshCityByLatLng(pos.latitude, pos.longitude);

      _allZones = HiveService.loadZones();
      _updateYouAreHereMarker();

      // Center on user once
      _moveMap(LatLng(pos.latitude, pos.longitude), 13.0);
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  void _subscribeToLocation() {
    final settings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    _posSub =
        Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
      _currentPosition = pos;
      _updateYouAreHereMarker();
      setState(() {}); // marker moved
    }, onError: (e) {
      debugPrint('Position stream error: $e');
    });
  }

  // -------------------- Viewport filtering --------------------
  // Don’t draw thousands of hexes when zoomed out.
  bool _shouldRenderHexes() {
    final z = _mapController.camera.zoom;
    // Show hexes starting at city-level zooms.
    return z >= 10.5;
  }

  void _updateVisiblePolys() {
    if (!_shouldRenderHexes()) {
      if (mounted) setState(() => _visiblePolygons = const []);
      return;
    }

    final cam = _mapController.camera;
    final bounds = cam.visibleBounds; // current viewport

    final List<Polygon> polys = [];
    for (final z in _allZones) {
      final b = z.boundary;
      if (b.isEmpty) continue;

      // quick centroid test (good enough for a small hex)
      double latSum = 0, lngSum = 0;
      for (final p in b) {
        latSum += p[0];
        lngSum += p[1];
      }
      final c = LatLng(latSum / b.length, lngSum / b.length);
      if (!bounds.contains(c)) continue;

      final poly = _toPolygon(z);
      if (poly != null) polys.add(poly);
    }

    if (mounted) setState(() => _visiblePolygons = polys);
  }

  // Debounce view updates during pan/zoom
  void _onMapEvent(MapEvent e) {
    if (e is! MapEventMove && e is! MapEventScrollWheelZoom) return;
    _viewDebounce?.cancel();
    _viewDebounce = Timer(const Duration(milliseconds: 120), _updateVisiblePolys);
  }

  // -------------------- Rendering helpers --------------------
  void _updateYouAreHereMarker() {
    _markers.removeWhere((m) => m.key == const ValueKey('me'));
    if (_currentPosition == null) return;

    final here = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    _markers.add(
      Marker(
        key: const ValueKey('me'),
        point: here,
        width: 80,
        height: 60,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'You are here',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 6, spreadRadius: 1)
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _moveMap(LatLng center, double zoom) {
    try {
      final cam = _mapController.camera;
      _mapController.move(cam.center != null ? center : center, zoom);
    } catch (_) {}
  }

  // Hex polygon: border-only when zoomed out; filled when zoomed in.
  Polygon? _toPolygon(HexZone z) {
    final b = z.boundary;
    if (b.isEmpty) return null;
    try {
      final pts = b.map((p) => LatLng(p[0], p[1])).toList();
      if (pts.length < 5 || pts.length > 8) return null; // hex-ish guard

      final color = Color(z.colorValue);
      final zoom = _mapController.camera.zoom;

      return Polygon(
        points: pts,
        color: zoom >= 12 ? color.withOpacity(0.35) : Colors.transparent,
        borderColor: color.withOpacity(0.8),
        borderStrokeWidth: zoom >= 12 ? 1.0 : 0.5,
      );
    } catch (_) {
      return null;
    }
  }

  void _zoomIn() {
    final cam = _mapController.camera;
    _mapController.move(cam.center, (cam.zoom + 1).clamp(2.0, 20.0));
  }

  void _zoomOut() {
    final cam = _mapController.camera;
    _mapController.move(cam.center, (cam.zoom - 1).clamp(2.0, 20.0));
  }

  // -------------------- UI --------------------
  @override
  Widget build(BuildContext context) {
    final hasPos = _currentPosition != null;
    final center = hasPos
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(33.8886, 35.4955); // Beirut default

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lebanon Hex Map'),
        backgroundColor: Colors.indigo,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 12.0,
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.all),
              onMapReady: () => _updateVisiblePolys(),
              onMapEvent: _onMapEvent, // debounce filtering on pan/zoom
            ),
            children: [
              // Reliable OSM tiles (simple endpoint)
              TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.example.safesteps_app',

  // Signature: (TileImage tile, Object error, StackTrace? stackTrace)
  errorTileCallback: (tile, error, stackTrace) {
    // If you want coordinates, use tile.coordinates (not x/y/z fields).
    // However, just logging the error is usually enough:
    // ignore: avoid_print
    print('Tile load error: $error'); 
  },
),


              // Only polygons inside the viewport (and only at zoom >= 10.5)
              PolygonLayer(
                polygons: _visiblePolygons,
                // polygonCulling: true, // optional if your flutter_map supports it
              ),

              // Red dot + label for user
              MarkerLayer(markers: _markers),
            ],
          ),

          // First-run warmup overlay
          if (_preparing)
            Positioned.fill(
              child: Container(
                color: Colors.black38,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(
                        'Preparing map… (first run only)',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Zoom buttons
          Positioned(
            right: 12,
            bottom: 24,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'zoom_in',
                  onPressed: _zoomIn,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom_out',
                  onPressed: _zoomOut,
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),

          // Recenter
          Positioned(
            right: 12,
            top: 12,
            child: FloatingActionButton(
              heroTag: 'locate_me',
              mini: true,
              onPressed: () {
                if (_currentPosition == null) return;
                final me = LatLng(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                );
                _moveMap(me, _mapController.camera.zoom);
              },
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}
