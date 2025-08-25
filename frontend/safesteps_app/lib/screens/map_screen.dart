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

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();

  Position? _currentPosition;
  StreamSubscription<Position>? _posSub;

  List<HexZone> _allZones = [];
  List<Polygon> _visiblePolygons = [];
  final List<Marker> _markers = [];

  bool _preparing = false;
  Timer? _periodicCityRefresh;
  Timer? _viewDebounce;

  late AnimationController _pulse;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _initFlow();

    // 👇 glowing animation
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.25, end: 0.55).animate(_pulse);
  }

  @override
  void dispose() {
    _periodicCityRefresh?.cancel();
    _posSub?.cancel();
    _viewDebounce?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _initFlow() async {
    await HiveService.initHive();

    if (!HiveService.isWarmupDone) {
      setState(() => _preparing = true);
      try {
        await HiveService.warmupAllLebanon();
      } finally {
        if (mounted) setState(() => _preparing = false);
      }
    }

    _allZones = HiveService.loadZones();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateVisiblePolys());

    await _acquireLocationOnceAndRefreshCity();
    _subscribeToLocation();

    _periodicCityRefresh =
        Timer.periodic(const Duration(minutes: 5), (_) async {
      if (_currentPosition == null) return;
      await HiveService.refreshCityByLatLng(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
      _allZones = HiveService.loadZones();
      _updateVisiblePolys();
    });
  }

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

      await HiveService.refreshCityByLatLng(pos.latitude, pos.longitude);

      _allZones = HiveService.loadZones();
      _updateYouAreHereMarker();
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

  void _updateVisiblePolys() {
    final cam = _mapController.camera;
    final bounds = cam.visibleBounds;

    final List<Polygon> polys = [];
    for (final z in _allZones) {
      if (z.boundary.isEmpty) continue;

      double latSum = 0, lngSum = 0;
      for (final p in z.boundary) {
        latSum += p[0];
        lngSum += p[1];
      }
      final c = LatLng(latSum / z.boundary.length, lngSum / z.boundary.length);
      if (!bounds.contains(c)) continue;

      final poly = _toPolygon(z);
      if (poly != null) polys.add(poly);
    }

    setState(() => _visiblePolygons = polys);
  }

  void _onMapEvent(MapEvent e) {
    if (e is! MapEventMove && e is! MapEventScrollWheelZoom) return;
    _viewDebounce?.cancel();
    _viewDebounce = Timer(const Duration(milliseconds: 120), _updateVisiblePolys);
  }

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

  Polygon? _toPolygon(HexZone z) {
    if (z.boundary.isEmpty) return null;
    try {
      final pts = z.boundary.map((p) => LatLng(p[0], p[1])).toList();
      if (pts.length < 5 || pts.length > 8) return null;
      final color = Color(z.colorValue);
      return Polygon(
        points: pts,
        color: color.withOpacity(_glowAnim.value), // 👈 glowing opacity
        borderColor: color.withOpacity(0.9),
        borderStrokeWidth: 1.0,
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

  @override
  Widget build(BuildContext context) {
    final hasPos = _currentPosition != null;
    final center = hasPos
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(33.8886, 35.4955);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lebanon Hex Map'),
        backgroundColor: Colors.indigo,
      ),
      body: AnimatedBuilder(
        animation: _glowAnim,
        builder: (context, _) {
          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 12.0,
                  interactionOptions:
                      const InteractionOptions(flags: InteractiveFlag.all),
                  onMapReady: _updateVisiblePolys,
                  onMapEvent: _onMapEvent,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c'],
                    userAgentPackageName: 'com.example.safesteps_app',
                  ),
                  PolygonLayer(
                    polygons: _visiblePolygons,
                    polygonCulling: true, // 👈 fixes lag
                  ),
                  MarkerLayer(markers: _markers),
                ],
              ),

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
          );
        },
      ),
    );
  }
}