import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as gc;

import '../services/routes_api.dart';

// ===== bounds of Lebanon (still enforced silently) =====
const double _LEB_MIN_LAT = 33.046;
const double _LEB_MAX_LAT = 34.693;
const double _LEB_MIN_LNG = 35.098;
const double _LEB_MAX_LNG = 36.623;

// enable Google map on web only when you provide a JS key and run with --dart-define=WEB_MAPS_ENABLED=true
const bool _WEB_MAPS_ENABLED = bool.fromEnvironment('WEB_MAPS_ENABLED', defaultValue: false);

// quick pick cities (for convenience)
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

enum PickTarget { origin, destination, position }

class SafetyNavigatorPage extends StatefulWidget {
  const SafetyNavigatorPage({super.key});
  @override
  State<SafetyNavigatorPage> createState() => _SafetyNavigatorPageState();
}

class _SafetyNavigatorPageState extends State<SafetyNavigatorPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // shared
  String mode = 'walking';
  int resolution = 9;
  String? cityContext; // optional hint for backend scoring

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
  }

  LatLng _clampLB(LatLng p) => LatLng(
        lat: p.lat.clamp(_LEB_MIN_LAT, _LEB_MAX_LAT).toDouble(),
        lng: p.lng.clamp(_LEB_MIN_LNG, _LEB_MAX_LNG).toDouble(),
      );

  // ======= helpers: geocoding / location / map =======
  Future<bool> _ensureLocPerm() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  Future<LatLng?> _geocode(String q) async {
    try {
      final list = await gc.locationFromAddress('$q, Lebanon');
      if (list.isEmpty) return null;
      final loc = list.first;
      return _clampLB(LatLng(lat: loc.latitude, lng: loc.longitude));
    } catch (_) {
      return null;
    }
  }

  void _panTo(LatLng p) {
    if (_map == null || _usePlaceholder) return;
    _map!.animateCamera(
      gmaps.CameraUpdate.newLatLng(gmaps.LatLng(p.lat, p.lng)),
    );
  }

  // ====== backend calls ======
  Future<void> _plan() async {
    setState(() { planBusy = true; planErr = null; planRes = null; });
    try {
      final res = await postSafestRoute(
        RouteRequest(
          origin: _origin,
          destination: _destination,
          city: (cityContext?.trim().isEmpty ?? true) ? null : cityContext,
          resolution: resolution,
          alternatives: alternatives,
          mode: mode,
          alpha: alpha,
        ),
      );
      setState(() => planRes = res);
      if (!_usePlaceholder) _drawPlanOnMap(res);
    } catch (e) {
      setState(() {
        planErr = e.toString();
        _polylines = {};
        _markers = {};
      });
    } finally {
      setState(() => planBusy = false);
    }
  }

  /// Find nearest safe hex from current **origin** and route there.
  Future<void> _planToSafestNearby() async {
    setState(() { planBusy = true; planErr = null; });
    try {
      final res = await postExitToSafety(ExitToSafetyRequest(
        position: _origin,
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

      if (res is ExitSuccess) {
        _destination = LatLng(lat: res.safeTarget.lat, lng: res.safeTarget.lng);
        _destLabel = 'Safest nearby';
        await _plan();
      } else if (res is ExitNotFound) {
        setState(() => planErr = res.detail);
      }
    } catch (e) {
      setState(() => planErr = e.toString());
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
      if (res is ExitSuccess && !_usePlaceholder) _drawExitOnMap(res);
      if (res is ExitNotFound) { _polylines = {}; _markers = {}; }
    } catch (e) {
      setState(() {
        exitErr = e.toString();
        _polylines = {};
        _markers = {};
      });
    } finally {
      setState(() => exitBusy = false);
    }
  }

  // ====== map drawing ======
  void _drawPlanOnMap(SafestResponse res) {
    final chosen = res.chosen;
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

    if (chosen.encodedPolyline != null) {
      final pts = decodePolyline(chosen.encodedPolyline!);
      final gpts = pts.map((p) => gmaps.LatLng(p.lat, p.lng)).toList();
      _polylines.add(gmaps.Polyline(
        polylineId: const gmaps.PolylineId('chosen'),
        points: gpts,
        width: 6,
      ));
      _map?.animateCamera(
        gmaps.CameraUpdate.newLatLngBounds(_bounds(gpts), 40),
      );
    }

    for (var i = 0; i < res.candidates.length; i++) {
      final c = res.candidates[i];
      if (c.encodedPolyline == null) continue;
      final pts = decodePolyline(c.encodedPolyline!);
      final gpts = pts.map((p) => gmaps.LatLng(p.lat, p.lng)).toList();
      _polylines.add(gmaps.Polyline(
        polylineId: gmaps.PolylineId('alt_$i'),
        points: gpts,
        width: 3,
      ));
    }
    setState(() {});
  }

  void _drawExitOnMap(ExitSuccess res) {
    final chosen = res.route.chosen;
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

    if (chosen.encodedPolyline != null) {
      final pts = decodePolyline(chosen.encodedPolyline!);
      final gpts = pts.map((p) => gmaps.LatLng(p.lat, p.lng)).toList();
      _polylines.add(gmaps.Polyline(
        polylineId: const gmaps.PolylineId('exit'),
        points: gpts,
        width: 6,
      ));
      _map?.animateCamera(
        gmaps.CameraUpdate.newLatLngBounds(_bounds(gpts), 40),
      );
    }
    setState(() {});
  }

  gmaps.LatLngBounds _bounds(List<gmaps.LatLng> pts) {
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return gmaps.LatLngBounds(
      southwest: gmaps.LatLng(minLat, minLng),
      northeast: gmaps.LatLng(maxLat, maxLng),
    );
  }

  // ====== map widget ======
  bool get _usePlaceholder => kIsWeb && !_WEB_MAPS_ENABLED;

  Widget _mapWidget() {
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
    return SizedBox(
      height: 260,
      child: gmaps.GoogleMap(
        mapType: gmaps.MapType.terrain,
        initialCameraPosition: gmaps.CameraPosition(
          target: gmaps.LatLng(_origin.lat, _origin.lng),
          zoom: 11,
        ),
        myLocationButtonEnabled: false,
        myLocationEnabled: false,
        markers: _markers,
        polylines: _polylines,
        onMapCreated: (c) => _map = c,
        onTap: (p) {
          if (_mapTapTarget == null) return;
          final clamped = _clampLB(LatLng(lat: p.latitude, lng: p.longitude));
          switch (_mapTapTarget!) {
            case PickTarget.origin:
              _origin = clamped; _originLabel = 'Pinned on map';
              break;
            case PickTarget.destination:
              _destination = clamped; _destLabel = 'Pinned on map';
              break;
            case PickTarget.position:
              _position = clamped; _posLabel = 'Pinned on map';
              break;
          }
          setState(() => _mapTapTarget = null);
        },
      ),
    );
  }

  // ====== UI ======
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
                  if (!await _ensureLocPerm()) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Location permission denied')),
                    );
                    return;
                  }
                  final p = await Geolocator.getCurrentPosition();
                  final clamped = _clampLB(LatLng(lat: p.latitude, lng: p.longitude));
                  if (_planTarget == PickTarget.origin) {
                    _origin = clamped; _originLabel = 'My location';
                  } else {
                    _destination = clamped; _destLabel = 'My location';
                  }
                  _panTo(clamped);
                  setState(() {});
                },
              ),
              FilledButton.icon(
                icon: Icon(_mapTapTarget == null ? Icons.add_location_alt_outlined : Icons.touch_app),
                label: Text(_mapTapTarget == null ? 'Pick on map' : 'Tap map…'),
                onPressed: _usePlaceholder ? null : () => setState(() => _mapTapTarget = _planTarget),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Swap'),
                onPressed: () {
                  final o = _origin; final ol = _originLabel;
                  _origin = _destination; _originLabel = _destLabel;
                  _destination = o; _destLabel = ol;
                  setState(() {});
                },
              ),
            ],
          ),

          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: _quick.map<Widget>((c) => ActionChip(
              label: Text(c.name),
              onPressed: () {
                final p = _clampLB(LatLng(lat: c.lat, lng: c.lng));
                if (_planTarget == PickTarget.origin) { _origin = p; _originLabel = c.name; }
                else { _destination = p; _destLabel = c.name; }
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
                onPressed: planBusy ? null : _planToSafestNearby,
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
                      DropdownMenuItem(value: 'bicycling', child: Text('Bicycling')),
                      DropdownMenuItem(value: 'transit', child: Text('Transit')),
                    ],
                    onChanged: (v) => setState(() => mode = v ?? 'walking'),
                  ),
                  SwitchListTile(
                    value: alternatives,
                    onChanged: (v) => setState(() => alternatives = v),
                    title: const Text('Show alternative routes'),
                  ),
                  Text('Safety ↔ Speed (alpha: ${alpha.toStringAsFixed(2)})'),
                  Slider(min: 0, max: 1, divisions: 100, value: alpha, onChanged: (v) => setState(() => alpha = v)),

                  // advanced
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
                  if (!await _ensureLocPerm()) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Location permission denied')),
                    );
                    return;
                  }
                  final p = await Geolocator.getCurrentPosition();
                  _position = _clampLB(LatLng(lat: p.latitude, lng: p.longitude));
                  _posLabel = 'My location';
                  _panTo(_position);
                  setState(() {});
                },
              ),
              FilledButton.icon(
                icon: Icon(_mapTapTarget == PickTarget.position ? Icons.touch_app : Icons.add_location_alt_outlined),
                label: Text(_mapTapTarget == PickTarget.position ? 'Tap map…' : 'Pick on map'),
                onPressed: _usePlaceholder ? null : () => setState(() => _mapTapTarget = PickTarget.position),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: _quick.map<Widget>((c) => ActionChip(
              label: Text(c.name),
              onPressed: () {
                final p = _clampLB(LatLng(lat: c.lat, lng: c.lng));
                _position = p; _posLabel = c.name; _panTo(p); setState(() {});
              },
            )).toList(),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.place),
              title: Text('Position: $_posLabel'),
              subtitle: const Text('I want the nearest safe place and route to it'),
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
                      DropdownMenuItem(value: 'bicycling', child: Text('Bicycling')),
                      DropdownMenuItem(value: 'transit', child: Text('Transit')),
                    ],
                    onChanged: (v) => setState(() => mode = v ?? 'walking'),
                  ),

                  // advanced options folded
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
                    onPressed: exitBusy ? null : _exitToSafety,
                    icon: const Icon(Icons.safety_check),
                    label: Text(exitBusy ? 'Finding safety…' : 'Find safest place & route'),
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

  // ====== search bottom sheet ======
  Future<void> _openSearchSheet(PickTarget target) async {
    final controller = TextEditingController();
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Search city or place in Lebanon', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'e.g. Hamra, Tripoli, Airport…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => Navigator.of(context).pop(controller.text.trim()),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Search'),
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            ),
          ],
        ),
      ),
    );

    final q = (res ?? '').trim();
    if (q.isEmpty) return;
    final p = await _geocode(q);
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No result for "$q"')),
      );
      return;
    }
    switch (target) {
      case PickTarget.origin:
        _origin = p; _originLabel = q; break;
      case PickTarget.destination:
        _destination = p; _destLabel = q; break;
      case PickTarget.position:
        _position = p; _posLabel = q; break;
    }
    _panTo(p);
    setState(() {});
  }
}
