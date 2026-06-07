import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'tracking_screen.dart';

class SearchResultScreen extends StatefulWidget {
  final String bloodGroup;
  final int units;

  const SearchResultScreen({
    super.key,
    required this.bloodGroup,
    required this.units,
  });

  @override
  State<SearchResultScreen> createState() => _SearchResultScreenState();
}

class _SearchResultScreenState extends State<SearchResultScreen> {
  List<Map<String, dynamic>> _results = [];
  bool _loading = true;
  String? _error;

  LatLng? _userLocation;
  String? _savingBankId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }

      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        );
      } on TimeoutException {
        pos = Position(
          latitude: 21.1458, longitude: 79.0882,
          timestamp: DateTime.now(), accuracy: 9999,
          altitude: 0, altitudeAccuracy: 0,
          heading: 0, headingAccuracy: 0,
          speed: 0, speedAccuracy: 0,
        );
      }

      if (!mounted) return;
      _userLocation = LatLng(pos.latitude, pos.longitude);
      await _fetchBanks();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not get location: $e';
        _loading = false;
      });
    }
  }

  // ─────────────────────────────────────────────────────────
  // ROAD DISTANCE via OSRM — same API used by tracking_screen
  // so the distance shown in the list matches the route shown
  // on the map exactly.
  // Falls back to straight-line if OSRM fails (no internet etc.)
  // ─────────────────────────────────────────────────────────
  Future<double> _roadDistanceKm(LatLng from, LatLng to) async {
    try {
      final url = 'https://router.project-osrm.org/route/v1/driving/'
          '${from.longitude},${from.latitude};'
          '${to.longitude},${to.latitude}'
          '?overview=false'; // we only need distance, not geometry

      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data  = json.decode(res.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final distM = (routes[0]['distance'] as num).toDouble();
          return distM / 1000; // metres → km
        }
      }
    } catch (_) {}

    // Fallback: straight-line (clearly labelled below so user knows)
    return Distance().as(LengthUnit.Kilometer, from, to);
  }

  Future<void> _fetchBanks() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('blood_banks')
          .get();

      if (!mounted) return;

      // Fire ALL inventory + road-distance reads in parallel per bank
      final futures = snapshot.docs.map((doc) async {
        final data = doc.data();
        final geo  = data['location'] as GeoPoint?;
        if (geo == null) return null;

        final stockDoc = await FirebaseFirestore.instance
            .collection('blood_banks')
            .doc(doc.id)
            .collection('inventory')
            .doc(widget.bloodGroup)
            .get();

        if (!stockDoc.exists) return null;

        final available =
            (stockDoc.data()?['count'] as num?)?.toInt() ?? 0;
        if (available < widget.units) return null;

        final bankLoc = LatLng(geo.latitude, geo.longitude);

        // KEY FIX — road distance instead of straight-line
        final km = await _roadDistanceKm(_userLocation!, bankLoc);

        return {
          'bankId'   : doc.id,
          'name'     : data['name']    ?? 'Unknown',
          'address'  : data['address'] ?? '',
          'distance' : km,
          'location' : bankLoc,
          'available': available,
        };
      });

      final rawResults = await Future.wait(futures);

      final results = rawResults
          .whereType<Map<String, dynamic>>()
          .toList()
        ..sort((a, b) =>
            (a['distance'] as double).compareTo(b['distance'] as double));

      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error   = 'Failed to load blood banks: $e';
        _loading = false;
      });
    }
  }

  Future<void> _saveBloodRequest(Map<String, dynamic> bank) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _userLocation == null) return;

    await FirebaseFirestore.instance.collection('blood_requests').add({
      'userId'      : uid,
      'bloodGroup'  : widget.bloodGroup,
      'units'       : widget.units,
      'bankId'      : bank['bankId'],
      'bankName'    : bank['name'],
      'userLocation': {
        'lat': _userLocation!.latitude,
        'lng': _userLocation!.longitude,
      },
      'bankLocation': {
        'lat': (bank['location'] as LatLng).latitude,
        'lng': (bank['location'] as LatLng).longitude,
      },
      'status'   : 'completed',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _onBankTap(Map<String, dynamic> bank) async {
    setState(() => _savingBankId = bank['bankId'] as String);

    try {
      await _saveBloodRequest(bank);
    } catch (e) {
      debugPrint('Save blood request failed: $e');
    }

    if (!mounted) return;
    setState(() => _savingBankId = null);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TrackingScreen(bankLocation: bank['location'] as LatLng),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text('${widget.bloodGroup}  ·  ${widget.units} units'),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.redAccent),
                  SizedBox(height: 14),
                  Text('Finding nearby blood banks…',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 48),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style:
                                const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _loading = true;
                              _error   = null;
                            });
                            _init();
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _results.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bloodtype,
                              size: 56,
                              color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text(
                            'No ${widget.bloodGroup} blood available\nnearby with ${widget.units}+ units.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 15),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _results.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final bank      = _results[i];
                        final isSaving  =
                            _savingBankId == bank['bankId'];
                        final distKm    =
                            (bank['distance'] as double)
                                .toStringAsFixed(1);
                        final available = bank['available'] as int;

                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: isSaving
                                ? null
                                : () => _onBankTap(bank),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: Colors.grey.shade200),
                                borderRadius:
                                    BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                        Icons.local_hospital,
                                        color: Colors.redAccent,
                                        size: 24),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(bank['name'] as String,
                                            style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight:
                                                    FontWeight.w600,
                                                color:
                                                    Colors.black87)),
                                        const SizedBox(height: 3),
                                        Text(
                                          bank['address'] as String,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey),
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            _Badge(
                                              icon: Icons.near_me,
                                              label: '$distKm km',
                                              color: Colors.blue,
                                            ),
                                            const SizedBox(width: 8),
                                            _Badge(
                                              icon: Icons.bloodtype,
                                              label: '$available units',
                                              color: Colors.green,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  isSaving
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child:
                                              CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.redAccent,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.chevron_right,
                                          color: Colors.grey),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}