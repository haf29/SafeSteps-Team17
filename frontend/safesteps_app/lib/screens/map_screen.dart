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

  List<Polygon> _visiblePolygons = [];
  final List<Marker> _markers = [];
  bool _preparing = false;
  Timer? _viewDebounce;
  bool _isFetchingTiles = false;

  late AnimationController _pulse;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _initFlow();

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.25, end: 0.55).animate(_pulse);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _viewDebounce?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _initFlow() async {
    setState(() => _preparing = true);
    await HiveService.initHive();
    await _acquireLocationOnceAndLoadTiles();
    _subscribeToLocation();
    setState(() => _preparing = false);
  }

  Future<void> _acquireLocationOnceAndLoadTiles() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _currentPosition = pos;

      _updateYouAreHereMarker();
      _moveMap(LatLng(pos.latitude, pos.longitude), 13.0);
      await _loadVisibleTiles();
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  void _subscribeToLocation() {
    const settings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen((pos) async {
      _currentPosition = pos;
      _updateYouAreHereMarker();
      setState(() {});
      await _loadVisibleTiles();
    });
  }

  Future<void> _loadVisibleTiles() async {
    if (_currentPosition == null) return;
    final b = _mapController.camera.visibleBounds;
    if (b == null) return;

    final tileIds = HiveService.tileIdsForRect(
      b.southWest.latitude,
      b.southWest.longitude,
      b.northEast.latitude,
      b.northEast.longitude,
    );

    final zonesToFetch = tileIds.where(HiveService.tileExpired).toList();
    if (zonesToFetch.isNotEmpty && !_isFetchingTiles) {
      _isFetchingTiles = true;
      try {
        final minLat = b.southWest.latitude;
        final minLng = b.southWest.longitude;
        final maxLat = b.northEast.latitude;
        final maxLng = b.northEast.longitude;
        await HiveService.fetchZonesByBBox(minLat, minLng, maxLat, maxLng);
      } finally {
        _isFetchingTiles = false;
      }
    }

    final zones = HiveService.loadZonesForTiles(tileIds);
    final polys = zones.map((z) {
      final pts = z.boundary.map((p) => LatLng(p[0], p[1])).toList();
      final color = Color(z.colorValue);
      return Polygon(
        points: pts,
        color: color.withOpacity(_glowAnim.value),
        borderColor: color.withOpacity(0.9),
        borderStrokeWidth: 1.0,
      );
    }).toList();

    setState(() => _visiblePolygons = polys);
  }

  void _onMapEvent(MapEvent e) {
    if (e is! MapEventMove && e is! MapEventScrollWheelZoom) return;
    _viewDebounce?.cancel();
    _viewDebounce = Timer(const Duration(milliseconds: 120), _loadVisibleTiles);
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
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(8)),
              child: const Text('You are here', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
            const SizedBox(height: 6),
            Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6, spreadRadius: 1)]),
            ),
          ],
        ),
      ),
    );
  }

  void _moveMap(LatLng center, double zoom) {
    try {
      _mapController.move(center, zoom);
    } catch (_) {}
  }

  void _zoomIn() => _mapController.move(_mapController.camera.center, (_mapController.camera.zoom + 1).clamp(2.0, 20.0));
  void _zoomOut() => _mapController.move(_mapController.camera.center, (_mapController.camera.zoom - 1).clamp(2.0, 20.0));

  @override
  Widget build(BuildContext context) {
    final center = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(33.8886, 35.4955);

    return Scaffold(
      appBar: AppBar(title: const Text('Lebanon Hex Map'), backgroundColor: Colors.indigo),
      body: AnimatedBuilder(
        animation: _glowAnim,
        builder: (context, _) => Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 12.0,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                onMapReady: _loadVisibleTiles,
                onMapEvent: _onMapEvent,
              ),
              children: [
                TileLayer(urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', subdomains: const ['a', 'b', 'c'], userAgentPackageName: 'com.example.safesteps_app'),
                PolygonLayer(polygons: _visiblePolygons, polygonCulling: true),
                MarkerLayer(markers: _markers),
              ],
            ),
            if (_preparing)
              Positioned.fill(
                child: Container(
                  color: Colors.black38,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            Positioned(
              right: 12,
              bottom: 24,
              child: Column(
                children: [
                  FloatingActionButton.small(heroTag: 'zoom_in', onPressed: _zoomIn, child: const Icon(Icons.add)),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(heroTag: 'zoom_out', onPressed: _zoomOut, child: const Icon(Icons.remove)),
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
                  _moveMap(LatLng(_currentPosition!.latitude, _currentPosition!.longitude), _mapController.camera.zoom);
                },
                child: const Icon(Icons.my_location),
              ),
            ),
          ],
        ),
      ),
    );
  }
}