import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Shows a map where the user can drag a pin to confirm their exact location.
/// Returns the confirmed [LatLng] when the user taps "Confirm Location",
/// or null if they cancel.
class LocationConfirmScreen extends StatefulWidget {
  const LocationConfirmScreen({super.key});

  @override
  State<LocationConfirmScreen> createState() => _LocationConfirmScreenState();
}

class _LocationConfirmScreenState extends State<LocationConfirmScreen> {
  final MapController _mapController = MapController();

  LatLng? _pinLocation;        // current draggable pin position
  bool _fetchingGps = true;    // true while getting initial position
  bool _dragging = false;      // true while user is dragging the pin
  String _addressLabel = '';   // reverse-geocoded address shown below pin
  bool _fetchingAddress = false;
  Timer? _addressDebounce;

  @override
  void initState() {
    super.initState();
    _getInitialLocation();
  }

  // ----------------------------------------
  // 1. GET INITIAL LOCATION (GPS or fallback)
  // ----------------------------------------
  Future<void> _getInitialLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }

      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
          timeLimit: const Duration(seconds: 8),
        );
      } on TimeoutException {
        // Chrome timed out — use a city-centre fallback; user will drag the pin
        pos = Position(
          latitude: 21.1458,   // Nagpur centre — change to your city
          longitude: 79.0882,
          timestamp: DateTime.now(),
          accuracy: 9999,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
      }

      final initialPos = LatLng(pos.latitude, pos.longitude);

      if (!mounted) return;
      setState(() {
        _pinLocation = initialPos;
        _fetchingGps = false;
      });

      _mapController.move(initialPos, 16);
      _reverseGeocode(initialPos);
    } catch (e) {
      if (!mounted) return;
      setState(() => _fetchingGps = false);
    }
  }

  // ----------------------------------------
  // 2. REVERSE GEOCODE PIN → ADDRESS LABEL
  // ----------------------------------------
  Future<void> _reverseGeocode(LatLng pos) async {
    setState(() => _fetchingAddress = true);
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json'
        '&lat=${pos.latitude}'
        '&lon=${pos.longitude}',
      );
      final res = await http.get(url,
          headers: {'User-Agent': 'emergency_blood_bank_app'});
      if (!mounted || res.statusCode != 200) return;
      final data = json.decode(res.body);
      final display = data['display_name'] as String? ?? '';
      // Shorten: take first two comma-separated parts
      final parts = display.split(',');
      setState(() {
        _addressLabel = parts.take(3).join(',').trim();
        _fetchingAddress = false;
      });
    } catch (_) {
      if (mounted) setState(() => _fetchingAddress = false);
    }
  }

  void _scheduleReverseGeocode(LatLng pos) {
    _addressDebounce?.cancel();
    _addressDebounce = Timer(const Duration(milliseconds: 600), () {
      _reverseGeocode(pos);
    });
  }

  // ----------------------------------------
  // 3. CONFIRM AND RETURN
  // ----------------------------------------
  void _confirm() {
    if (_pinLocation == null) return;
    Navigator.of(context).pop(_pinLocation);
  }

  @override
  void dispose() {
    _addressDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Confirm Your Location'),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _fetchingGps
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.redAccent),
                  SizedBox(height: 16),
                  Text('Getting your location…',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : Stack(
              children: [
                // ── MAP ─────────────────────────────────────────
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    center: _pinLocation ?? const LatLng(21.1458, 79.0882),
                    zoom: 16,
                    keepAlive: true,
                    // Update pin whenever the map is moved (drag-map-to-pin style)
                    onPositionChanged: (pos, hasGesture) {
                      if (!hasGesture || pos.center == null) return;
                      setState(() {
                        _pinLocation = pos.center;
                        _dragging = true;
                      });
                      _scheduleReverseGeocode(pos.center!);
                    },
                    onMapEvent: (event) {
                      if (event is MapEventMoveEnd ||
                          event is MapEventFlingAnimationEnd) {
                        setState(() => _dragging = false);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.emergency_blood_bank',
                    ),
                  ],
                ),

                // ── CENTRE PIN (always at screen centre) ────────
                IgnorePointer(
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      // Pin lifts up slightly while dragging
                      transform: Matrix4.translationValues(
                          0, _dragging ? -28 : -24, 0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.redAccent.withOpacity(0.4),
                                  blurRadius: _dragging ? 16 : 8,
                                  spreadRadius: _dragging ? 4 : 1,
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(8),
                            child: const Icon(Icons.person_pin_circle,
                                color: Colors.white, size: 28),
                          ),
                          // Pin stem
                          Container(
                            width: 2.5,
                            height: 12,
                            color: Colors.redAccent,
                          ),
                          // Shadow dot on ground
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: _dragging ? 6 : 10,
                            height: _dragging ? 3 : 5,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── TOP INSTRUCTION BANNER ───────────────────────
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.touch_app, size: 16, color: Colors.redAccent),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Drag the map to move the pin to your exact location',
                            style: TextStyle(fontSize: 13, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── BOTTOM PANEL ─────────────────────────────────
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.07),
                          blurRadius: 12,
                          offset: const Offset(0, -3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Drag handle
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),

                        const Text(
                          'Selected location',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),

                        // Address label
                        Row(
                          children: [
                            const Icon(Icons.location_on,
                                size: 16, color: Colors.redAccent),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _fetchingAddress
                                  ? const SizedBox(
                                      height: 14,
                                      width: 120,
                                      child: LinearProgressIndicator(
                                        color: Colors.redAccent,
                                        backgroundColor: Color(0xFFFFEEEE),
                                      ),
                                    )
                                  : Text(
                                      _addressLabel.isNotEmpty
                                          ? _addressLabel
                                          : (_pinLocation != null
                                              ? '${_pinLocation!.latitude.toStringAsFixed(5)}, '
                                                '${_pinLocation!.longitude.toStringAsFixed(5)}'
                                              : 'Unknown'),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black87,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Confirm button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _pinLocation != null ? _confirm : null,
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text(
                              'Confirm This Location',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
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
}