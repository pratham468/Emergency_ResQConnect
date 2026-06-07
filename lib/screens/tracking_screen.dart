import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class TrackingScreen extends StatefulWidget {
  final LatLng bankLocation;

  const TrackingScreen({
    super.key,
    required this.bankLocation,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final MapController _mapController = MapController();

  LatLng? _userPos;
  List<LatLng> _routePoints = [];

  // FIX 8 — ETA / distance from OSRM
  String _etaLabel = '';
  String _distanceLabel = '';

  // FIX 4 — live location stream instead of one-shot fetch
  StreamSubscription<Position>? _locationStream;

  // FIX 5 — debounce route so we don't hammer OSRM on every GPS tick
  Timer? _routeDebounce;

  // Track last known position to skip no-op updates (~5 m threshold)
  LatLng? _lastPos;

  // Whether the map has been fitted at least once
  bool _hasFittedOnce = false;

  // Whether we're still getting the very first location fix
  bool _initialising = true;

  @override
  void initState() {
    super.initState();
    _startLiveTracking();
  }

  // ─────────────────────────────────────────────────────────
  // FIX 1 + 4: request permission THEN open a GPS stream
  // ─────────────────────────────────────────────────────────
  Future<void> _startLiveTracking() async {
    // Permission check (FIX 1)
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showError('Location services are disabled.');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showError('Location permission denied.');
      return;
    }

    // FIX 4 — stream instead of one-shot getCurrentPosition
    _locationStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // only fire when moved ≥5 metres
      ),
    ).listen((pos) {
      if (!mounted) return;

      final newPos = LatLng(pos.latitude, pos.longitude);

      // Skip if hasn't moved meaningfully
      if (_lastPos != null &&
          (_lastPos!.latitude - newPos.latitude).abs() < 0.00005 &&
          (_lastPos!.longitude - newPos.longitude).abs() < 0.00005) {
        return;
      }

      _lastPos = newPos;

      // FIX 6 — setState immediately so user marker + spinner update
      setState(() {
        _userPos = newPos;
        _initialising = false;
      });

      // Fit map only once when first position arrives (FIX 2)
      if (!_hasFittedOnce) {
        _hasFittedOnce = true;
        // Delay one frame so the map has rendered before fitBounds
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitMap());
      }

      // FIX 5 — debounce route fetch to 1 second after movement settles
      _routeDebounce?.cancel();
      _routeDebounce = Timer(const Duration(seconds: 1), _fetchRoute);
    });
  }

  // ─────────────────────────────────────────────────────────
  // ROUTE FETCH — called after debounce
  // ─────────────────────────────────────────────────────────
  Future<void> _fetchRoute() async {
    if (_userPos == null || !mounted) return;

    final url = 'https://router.project-osrm.org/route/v1/driving/'
        '${_userPos!.longitude},${_userPos!.latitude};'
        '${widget.bankLocation.longitude},${widget.bankLocation.latitude}'
        '?overview=full&geometries=geojson';

    try {
      final res = await http.get(Uri.parse(url));
      if (!mounted || res.statusCode != 200) return;

      final data = json.decode(res.body);
      final route = data['routes'][0];
      final coords = route['geometry']['coordinates'] as List<dynamic>;

      // FIX 8 — ETA & distance (free from OSRM, was being discarded)
      final durationSec = (route['duration'] as num).toDouble();
      final distanceM = (route['distance'] as num).toDouble();
      final etaMin = (durationSec / 60).ceil();
      final distKm = (distanceM / 1000).toStringAsFixed(1);

      final newPoints = coords
          .map<LatLng>((c) => LatLng(
                (c[1] as num).toDouble(),
                (c[0] as num).toDouble(),
              ))
          .toList();

      if (!mounted) return;

      setState(() {
        _routePoints = newPoints;
        _etaLabel = '$etaMin min';
        _distanceLabel = '$distKm km';
      });
    } catch (e) {
      debugPrint('Route error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────
  // FIX 2 — called via postFrameCallback so map is ready
  // ─────────────────────────────────────────────────────────
  void _fitMap() {
    if (_userPos == null || !mounted) return;
    final bounds =
        LatLngBounds.fromPoints([_userPos!, widget.bankLocation]);
    _mapController.fitBounds(
      bounds,
      options: const FitBoundsOptions(padding: EdgeInsets.all(60)),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() => _initialising = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _locationStream?.cancel();
    _routeDebounce?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // FIX 3 — show spinner only during the very first GPS fix
    if (_initialising) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.redAccent),
              SizedBox(height: 16),
              Text('Getting your location…',
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Route to Blood Bank'),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [

          // ── ETA / DISTANCE STRIP ─────────────────────────
          if (_etaLabel.isNotEmpty)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  _InfoChip(
                    icon: Icons.timer_outlined,
                    label: _etaLabel,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(width: 12),
                  _InfoChip(
                    icon: Icons.straighten,
                    label: _distanceLabel,
                    color: Colors.blueAccent,
                  ),
                  const Spacer(),
                  // Re-centre both markers
                  IconButton(
                    onPressed: _fitMap,
                    icon: const Icon(Icons.fit_screen,
                        color: Colors.grey, size: 22),
                    tooltip: 'Show both markers',
                  ),
                ],
              ),
            ),

          // ── MAP ──────────────────────────────────────────
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                center: _userPos ?? widget.bankLocation,
                zoom: 14,
                keepAlive: true,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  // FIX 9 — required by OSM usage policy
                  userAgentPackageName:
                      'com.example.emergency_blood_bank',
                ),
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 5,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (_userPos != null)
                      Marker(
                        point: _userPos!,
                        width: 50,
                        height: 50,
                        child: const Icon(Icons.person_pin_circle,
                            color: Colors.blue, size: 45),
                      ),
                    Marker(
                      point: widget.bankLocation,
                      width: 50,
                      height: 50,
                      child: const Icon(Icons.local_hospital,
                          color: Colors.red, size: 45),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── BOTTOM PANEL ─────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                // FIX 7 — pop only 1 screen (back to whoever opened this)
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('Done',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// ETA / DISTANCE CHIP — same as driver navigation screen
// ─────────────────────────────────────────────────────────
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}