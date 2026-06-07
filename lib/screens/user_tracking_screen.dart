import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class UserTrackingScreen extends StatefulWidget {
  final String requestId;

  const UserTrackingScreen({super.key, required this.requestId});

  @override
  State<UserTrackingScreen> createState() => _UserTrackingScreenState();
}

class _UserTrackingScreenState extends State<UserTrackingScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final MapController _mapController = MapController();

  StreamSubscription<DocumentSnapshot>? _reqListener;
  StreamSubscription<DocumentSnapshot>? _driverListener;

  LatLng? _userPos;
  LatLng? _driverPos;

  String? _driverId;
  String _status = 'pending';

  // 🔥 DRIVER DETAILS
  String? _driverPhone;
  String? _ambulanceNo;
  String? _driverName; // Added driver name variable

  List<LatLng> _routePoints = [];

  double? _lastDriverLat;
  double? _lastDriverLng;

  Timer? _routeDebounce;
  bool _hasFittedOnce = false;

  @override
  void initState() {
    super.initState();
    _listenToRequest();
  }

  void _listenToRequest() {
    _reqListener = _firestore
        .collection('emergency_requests')
        .doc(widget.requestId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;

      final data = snap.data()!;
      final loc = data['userLocation'];
      final newStatus = data['status'] ?? 'pending';
      final assigned = data['assignedAmbulance'] ?? '';

      bool rebuild = false;

      if (loc != null) {
        final newPos = LatLng(
          (loc['lat'] as num).toDouble(),
          (loc['lng'] as num).toDouble(),
        );

        if (_userPos == null ||
            _userPos!.latitude != newPos.latitude ||
            _userPos!.longitude != newPos.longitude) {
          _userPos = newPos;
          rebuild = true;
        }
      }

      if (_status != newStatus) {
        _status = newStatus;
        rebuild = true;
      }

      if (_status == "assigned" &&
          assigned.isNotEmpty &&
          assigned != _driverId) {
        _driverId = assigned;
        _hasFittedOnce = false;
        _listenToDriver(assigned);
      }

      if (rebuild) setState(() {});
    });
  }

  void _listenToDriver(String id) {
    _driverListener?.cancel();

    _driverListener = _firestore
        .collection('ambulances')
        .doc(id)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;

      final data = snap.data()!;
      final loc = data["currentLocation"];

      // 🔥 UPDATED: FETCH DRIVER NAME
      _driverPhone = data["phone"];
      _ambulanceNo = data["ambulanceNo"];
      _driverName = data["name"]; // Assuming 'name' field exists in 'ambulances' collection

      if (loc == null) return;

      final lat = (loc['lat'] as num).toDouble();
      final lng = (loc['lng'] as num).toDouble();

      if (_lastDriverLat != null &&
          (_lastDriverLat! - lat).abs() < 0.00005 &&
          (_lastDriverLng! - lng).abs() < 0.00005) {
        return;
      }

      _lastDriverLat = lat;
      _lastDriverLng = lng;
      _driverPos = LatLng(lat, lng);

      setState(() {});

      if (!_hasFittedOnce && _userPos != null) {
        _hasFittedOnce = true;
        _fitMap();
      }

      _routeDebounce?.cancel();
      _routeDebounce = Timer(const Duration(seconds: 1), () {
        if (_driverPos != null && _userPos != null) {
          _fetchRoute(_driverPos!, _userPos!);
        }
      });
    });
  }

  Future<void> _fetchRoute(LatLng start, LatLng end) async {
    final url = "http://router.project-osrm.org/route/v1/driving/"
        "${start.longitude},${start.latitude};"
        "${end.longitude},${end.latitude}"
        "?overview=full&geometries=geojson";

    try {
      final res = await http.get(Uri.parse(url));
      if (!mounted || res.statusCode != 200) return;

      final data = json.decode(res.body);
      final coords = data["routes"][0]["geometry"]["coordinates"];

      _routePoints = coords
          .map<LatLng>((c) => LatLng(
                (c[1] as num).toDouble(),
                (c[0] as num).toDouble(),
              ))
          .toList();

      setState(() {});
    } catch (e) {
      debugPrint("Route error: $e");
    }
  }

  void _fitMap() {
    if (_driverPos == null || _userPos == null) return;
    final bounds = LatLngBounds.fromPoints([_driverPos!, _userPos!]);
    _mapController.fitBounds(
      bounds,
      options: const FitBoundsOptions(padding: EdgeInsets.all(60)),
    );
  }

  @override
  void dispose() {
    _routeDebounce?.cancel();
    _reqListener?.cancel();
    _driverListener?.cancel();
    super.dispose();
  }

  // ────────────────────────────────────────────────────────
  // UI COMPONENTS
  // ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final driverAvailable = _driverPos != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Track Ambulance"),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                zoom: 14,
                center: _userPos ?? LatLng(19.0760, 72.8777),
              ),
              children: [
                TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  userAgentPackageName: "com.example.emergency_blood_bank",
                ),
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 5,
                        color: Colors.blueAccent,
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
                    if (_driverPos != null)
                      Marker(
                        point: _driverPos!,
                        width: 50,
                        height: 50,
                        child: const Icon(Icons.local_shipping,
                            color: Colors.red, size: 45),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // 🔥 UPDATED BOTTOM PANEL
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        driverAvailable ? "Driver is on the way" : "Waiting for driver...",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: driverAvailable ? Colors.green : Colors.orange,
                        ),
                      ),
                      if (driverAvailable)
                        const Icon(Icons.verified, color: Colors.blue, size: 20),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (driverAvailable) ...[
                    // Driver Details Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          _buildInfoRow(Icons.person, Colors.blue, "Driver Name", _driverName ?? 'N/A'),
                          const Divider(height: 24),
                          _buildInfoRow(Icons.local_hospital, Colors.red, "Ambulance No", _ambulanceNo ?? 'N/A'),
                          const Divider(height: 24),
                          _buildInfoRow(Icons.phone, Colors.green, "Contact Number", _driverPhone ?? 'N/A'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _userPos != null ? () => _mapController.move(_userPos!, 16) : null,
                      icon: const Icon(Icons.my_location),
                      label: const Text("Center on My Location"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget for aligned info rows
  Widget _buildInfoRow(IconData icon, Color iconColor, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
            ],
          ),
        ),
      ],
    );
  }
}