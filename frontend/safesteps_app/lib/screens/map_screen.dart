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

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();

  Position? _currentPosition;
  StreamSubscription<Position>? _posSub;

  List<Polygon> _visiblePolygons = [];
  final List<Marker> _markers = [];

  bool _firstViewportLoaded = false;   // first-load overlay
  bool _isFetchingTiles = false;       // prevent concurrent bbox fetches
  Timer? _viewDebounce;                // debounce for pan/zoom
  bool _shownNetErrorOnce = false;     // avoid snackbar spam

  late AnimationController _pulse;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.25, end: 0.55).animate(_pulse);

    _initFlow();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _viewDebounce?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _initFlow() async {
    await HiveService.initHive();
    await _acquireLocationOnce();

    if (mounted) {
      final center = _currentPosition != null
          ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
          : const LatLng(33.8886, 35.4955); // Beirut fallback
      _safeMove(center, 12.0);
      await _loadVisibleTiles(firstLoad: true);
    }

    _subscribeToLocation();
  }

  Future<void> _acquireLocationOnce() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _currentPosition = pos;
      _updateYouAreHereMarker();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  void _subscribeToLocation() {
    const settings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) async {
        _currentPosition = pos;
        _updateYouAreHereMarker();
        if (mounted) setState(() {});
        _debouncedLoad();
      },
      onError: (e) => debugPrint('Position stream error: $e'),
    );
  }

  void _debouncedLoad() {
    _viewDebounce?.cancel();
    _viewDebounce = Timer(const Duration(milliseconds: 150), _loadVisibleTiles);
  }

  Future<void> _loadVisibleTiles({bool firstLoad = false}) async {
    final cam = _mapController.camera;
    final b = cam.visibleBounds;
    if (b == null) return;

    final tileIds = HiveService.tileIdsForRect(
      b.southWest.latitude,
      b.southWest.longitude,
      b.northEast.latitude,
      b.northEast.longitude,
    );

    final toFetch = tileIds.where(HiveService.tileExpired).toList();
    if (toFetch.isNotEmpty && !_isFetchingTiles) {
      _isFetchingTiles = true;
      try {
        await HiveService.fetchZonesByBBox(
          b.southWest.latitude,
          b.southWest.longitude,
          b.northEast.latitude,
          b.northEast.longitude,
        );
      } catch (e) {
        debugPrint('fetchZonesByBBox error: $e');
        if (!_shownNetErrorOnce && mounted) {
          _shownNetErrorOnce = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Network error loading map zones')),
          );
        }
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
        color: color.withOpacity(_glowAnim.value), // subtle breathing effect
        borderColor: color.withOpacity(0.9),
        borderStrokeWidth: 1.0,
      );
    }).toList();

    if (!mounted) return;
    setState(() {
      _visiblePolygons = polys;
      if (firstLoad) _firstViewportLoaded = true;
    });
  }

  void _onMapEvent(MapEvent e) {
    if (e is MapEventMove || e is MapEventScrollWheelZoom || e is MapEventRotate) {
      _debouncedLoad();
    }
  }

  void _updateYouAreHereMarker() {
    _markers.removeWhere((m) => m.key == const ValueKey('me'));
    if (_currentPosition == null) return;

    final here = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

    // No overflow: use FittedBox and a slightly larger marker box
    _markers.add(
      Marker(
        key: const ValueKey('me'),
        point: here,
        width: 120,
        height: 64,
        alignment: Alignment.topCenter,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.70),
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
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6, spreadRadius: 1)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _safeMove(LatLng center, double zoom) {
    try {
      _mapController.move(center, zoom.clamp(2.0, 20.0));
    } catch (_) {}
  }

  void _zoomIn() {
    final cam = _mapController.camera;
    _safeMove(cam.center, cam.zoom + 1);
  }

  void _zoomOut() {
    final cam = _mapController.camera;
    _safeMove(cam.center, cam.zoom - 1);
  }

  @override
  Widget build(BuildContext context) {
    final center = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(33.8886, 35.4955); // Beirut fallback

    return Scaffold(
      // 🔇 No AppBar here — main.dart provides the global nav
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _glowAnim,
          builder: (context, _) {
            return Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 12.0,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                    onMapReady: () => _loadVisibleTiles(firstLoad: !_firstViewportLoaded),
                    onMapEvent: _onMapEvent,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c'],
                      userAgentPackageName: 'com.example.safesteps_app',
                    ),
                    PolygonLayer(
                      polygons: _visiblePolygons,
                      polygonCulling: true,
                    ),
                    MarkerLayer(markers: _markers),
                  ],
                ),

                // First-time loader overlay
                if (!_firstViewportLoaded)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black26,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),

                // Zoom controls
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

                // Locate-me
                Positioned(
                  right: 12,
                  top: 12,
                  child: FloatingActionButton(
                    heroTag: 'locate_me',
                    mini: true,
                    onPressed: () {
                      if (_currentPosition == null) return;
                      final cam = _mapController.camera;
                      _safeMove(
                        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                        cam.zoom,
                      );
                    },
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
