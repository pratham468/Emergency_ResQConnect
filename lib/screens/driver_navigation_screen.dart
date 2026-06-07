import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class DriverNavigationScreen extends StatefulWidget {
  final String requestId;
  final String driverId;
  final double userLat;
  final double userLng;

  const DriverNavigationScreen({
    super.key,
    required this.requestId,
    required this.driverId,
    required this.userLat,
    required this.userLng,
  });

  @override
  State<DriverNavigationScreen> createState() => _DriverNavigationScreenState();
}

class _DriverNavigationScreenState extends State<DriverNavigationScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final MapController _mapController = MapController();

  StreamSubscription<DocumentSnapshot>? _driverListener;
  StreamSubscription<DocumentSnapshot>? _requestListener;

  LatLng? _driverPos;
  LatLng? _userPos;
  List<LatLng> _routePoints = [];

  //use LatLng objects instead of 4 separate doubles
  LatLng? _lastDriverPos;
  LatLng? _lastUserPos;

  Timer? _routeDebounce;
  bool _hasFittedOnce = false;

  //ETA & distance from OSRM (already in response, was being discarded)
  String _etaLabel = '';
  String _distanceLabel = '';

  //prevent accidental double-tap on Complete Trip
  bool _completing = false;

  //track status to auto-exit if cancelled externally
  String _requestStatus = 'assigned';

  @override
  void initState() {
    super.initState();
    _userPos = LatLng(widget.userLat, widget.userLng);
    _lastUserPos = _userPos;

    _listenToDriverLocation();
    _listenToRequest(); // FIX 3: one listener handles both userLocation + status
  }

  // ─────────────────────────────────────────────────────────
  // DRIVER LOCATION — ambulances/{driverId}
  // ─────────────────────────────────────────────────────────
  void _listenToDriverLocation() {
    _driverListener = _firestore
        .collection('ambulances')
        .doc(widget.driverId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;

      final loc = snap.data()?['currentLocation'] as Map<String, dynamic>?;
      if (loc == null) return;

      final newLat = (loc['lat'] as num).toDouble();
      final newLng = (loc['lng'] as num).toDouble();

      // FIX 4 — skip if hasn't moved meaningfully (~5 metres)
      if (_lastDriverPos != null &&
          (_lastDriverPos!.latitude - newLat).abs() < 0.00005 &&
          (_lastDriverPos!.longitude - newLng).abs() < 0.00005) {
        return;
      }

      _lastDriverPos = LatLng(newLat, newLng);
      _driverPos = _lastDriverPos;

      setState(() {});

      if (!_hasFittedOnce && _userPos != null) {
        _hasFittedOnce = true;
        _fitBounds();
      }

      _scheduleRouteFetch();
    });
  }

  // ─────────────────────────────────────────────────────────
  // REQUEST LISTENER — emergency_requests/{requestId}
  // FIX 3: replaces the old separate _userListener.
  //         Reads userLocation AND status from one snapshot.
  // FIX 6: auto-exits if status becomes completed/cancelled.
  // ─────────────────────────────────────────────────────────
  void _listenToRequest() {
    _requestListener = _firestore
        .collection('emergency_requests')
        .doc(widget.requestId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;

      final data = snap.data()!;

      // FIX 6 — handle external trip end
      final status = data['status'] as String? ?? '';
      if (status != _requestStatus) {
        _requestStatus = status;
        if (status == 'completed' || status == 'cancelled') {
          _onTripEndedExternally(status);
          return;
        }
      }

      // FIX 3 — user location from same snapshot (no extra listener needed)
      final loc = data['userLocation'] as Map<String, dynamic>?;
      if (loc == null) return;

      final newLat = (loc['lat'] as num).toDouble();
      final newLng = (loc['lng'] as num).toDouble();

      if (_lastUserPos != null &&
          (_lastUserPos!.latitude - newLat).abs() < 0.00005 &&
          (_lastUserPos!.longitude - newLng).abs() < 0.00005) {
        return;
      }

      _lastUserPos = LatLng(newLat, newLng);
      _userPos = _lastUserPos;

      setState(() {});
      _scheduleRouteFetch();
    });
  }

  // FIX 6 — inform driver and exit cleanly
  void _onTripEndedExternally(String status) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(status == 'completed' ? 'Trip Completed' : 'Trip Cancelled'),
        content: Text(status == 'completed'
            ? 'This trip has been marked as completed.'
            : 'This emergency request was cancelled.'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // close dialog
              if (mounted) {
                Navigator.pop(context); // close NavigationScreen
                Navigator.pop(context); // close IncomingRequest
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // ROUTE — debounced, updates every time fresh data arrives
  // ─────────────────────────────────────────────────────────
  void _scheduleRouteFetch() {
    _routeDebounce?.cancel();
    _routeDebounce = Timer(const Duration(seconds: 1), () {
      if (_driverPos != null && _userPos != null) {
        _fetchRoute(_driverPos!, _userPos!);
      }
    });
  }

  Future<void> _fetchRoute(LatLng start, LatLng end) async {
    final url = 'http://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson';

    try {
      final res = await http.get(Uri.parse(url));
      if (!mounted || res.statusCode != 200) return;

      final data = json.decode(res.body);
      final route = data['routes'][0];
      final coords = route['geometry']['coordinates'] as List<dynamic>;

      // FIX 5 — OSRM gives duration & distance for free, use them
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

      // FIX 2 — always update; don't skip based on point count
      setState(() {
        _routePoints = newPoints;
        _etaLabel = '$etaMin min';
        _distanceLabel = '$distKm km';
      });
    } catch (e) {
      debugPrint('Route fetch error: $e');
    }
  }

  void _fitBounds() {
    if (_driverPos == null || _userPos == null) return;
    final bounds = LatLngBounds.fromPoints([_driverPos!, _userPos!]);
    _mapController.fitBounds(
      bounds,
      options: const FitBoundsOptions(padding: EdgeInsets.all(60)),
    );
  }

  // ─────────────────────────────────────────────────────────
  // COMPLETE TRIP
  // FIX 1 — confirmation dialog + loading state
  // FIX 7 — mounted guard between the two async Firestore writes
  // ─────────────────────────────────────────────────────────
  Future<void> _completeTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Complete Trip?'),
        content: const Text(
            'Mark this trip as complete and set yourself back to available?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _completing = true);

    try {
      await _firestore
          .collection('emergency_requests')
          .doc(widget.requestId)
          .update({'status': 'completed'});

      // FIX 7 — guard between two sequential awaits
      if (!mounted) return;

      await _firestore
          .collection('ambulances')
          .doc(widget.driverId)
          .update({'status': 'available'});

      if (mounted) {
        // Pop exactly 2 screens:
        // NavigationScreen → IncomingRequest → DriverDashboard (stop here)
        Navigator.pop(context); // close NavigationScreen
        Navigator.pop(context); // close IncomingRequest
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _completing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to complete trip: $e')),
      );
    }
  }

  @override
  void dispose() {
    _routeDebounce?.cancel();
    _driverListener?.cancel();
    _requestListener?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigate to Patient'),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [

          // FIX 5 — ETA / distance strip (only visible once route loads)
          if (_etaLabel.isNotEmpty)
            Container(
              color: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                  IconButton(
                    onPressed: _fitBounds,
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
                center: _driverPos ??
                    _userPos ??
                    const LatLng(19.0760, 72.8777),
                zoom: 14,
                keepAlive: true,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.emergency_blood_bank',
                ),
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        color: Colors.blue,
                        strokeWidth: 5,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (_driverPos != null)
                      Marker(
                        point: _driverPos!,
                        width: 50,
                        height: 50,
                        child: const Icon(Icons.local_taxi,
                            color: Colors.red, size: 40),
                      ),
                    if (_userPos != null)
                      Marker(
                        point: _userPos!,
                        width: 50,
                        height: 50,
                        child: const Icon(Icons.person_pin_circle,
                            color: Colors.blue, size: 40),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── COMPLETE BUTTON ───────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _completing ? null : _completeTrip,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.green.shade200,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _completing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('Complete Trip',
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
// ETA / DISTANCE CHIP
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