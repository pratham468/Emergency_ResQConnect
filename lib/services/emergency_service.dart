// lib/services/emergency_service.dart
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class EmergencyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // FIX 5 — track active timeout timers keyed by requestId so they can be
  // cancelled when the driver accepts before the 14s window expires
  final Map<String, Timer> _timeoutTimers = {};

  // ─────────────────────────────────────────────────────────
  // CREATE EMERGENCY REQUEST
  // FIX 2+3 — auto-reads userId from FirebaseAuth so callers
  //            never forget to pass it
  // ─────────────────────────────────────────────────────────
  Future<String> createEmergencyRequest({
    required double lat,
    required double lng,
    String? userId, // optional override; falls back to current user
  }) async {
    // FIX 3 — get uid from auth if not provided
    final uid = userId?.isNotEmpty == true
        ? userId!
        : (FirebaseAuth.instance.currentUser?.uid ?? '');

    final reqRef    = _firestore.collection('emergency_requests').doc();
    final requestId = reqRef.id;

    await reqRef.set({
      'requestId'        : requestId,
      'userId'           : uid,
      'userLocation'     : {'lat': lat, 'lng': lng},
      'assignedAmbulance': '',
      'status'           : 'pending', // pending → awaiting_driver → assigned → completed
      'triedDrivers'     : [],
      'createdAt'        : FieldValue.serverTimestamp(),
      'assignedAt'       : null,
    });

    await _assignNearestDriver(requestId);
    return requestId;
  }

  // ─────────────────────────────────────────────────────────
  // ASSIGN NEAREST AVAILABLE DRIVER
  // ─────────────────────────────────────────────────────────
  Future<void> _assignNearestDriver(String requestId) async {
    final reqRef  = _firestore.collection('emergency_requests').doc(requestId);
    final reqSnap = await reqRef.get();
    if (!reqSnap.exists) return;

    final data    = reqSnap.data()!;
    final userLoc = data['userLocation'] as Map<String, dynamic>?;
    if (userLoc == null) return;

    final tried   = List<String>.from(data['triedDrivers'] ?? []);
    final userLat = (userLoc['lat'] as num).toDouble();
    final userLng = (userLoc['lng'] as num).toDouble();

    final ambSnap = await _firestore
        .collection('ambulances')
        .where('status', isEqualTo: 'available')
        .get();

    if (ambSnap.docs.isEmpty) {
      await reqRef.update({
        'status'           : 'pending',
        'assignedAmbulance': '',
        'assignedAt'       : null,
      });
      return;
    }

    double  bestDist     = double.infinity;
    String? bestDriverId;

    for (final doc in ambSnap.docs) {
      final driverId = doc.id;
      if (tried.contains(driverId)) continue;

      final loc = doc.data()['currentLocation'] as Map<String, dynamic>?;
      if (loc == null) continue;

      final dLat = (loc['lat'] as num).toDouble();
      final dLng = (loc['lng'] as num).toDouble();
      final dist = _haversineDistance(userLat, userLng, dLat, dLng);

      if (dist < bestDist) {
        bestDist     = dist;
        bestDriverId = driverId;
      }
    }

    if (bestDriverId == null) {
      await reqRef.update({
        'status'           : 'pending',
        'assignedAmbulance': '',
        'assignedAt'       : null,
      });
      return;
    }

    await reqRef.update({
      'assignedAmbulance': bestDriverId,
      'status'           : 'awaiting_driver',
      'triedDrivers'     : FieldValue.arrayUnion([bestDriverId]),
      'assignedAt'       : FieldValue.serverTimestamp(),
    });

    _startTimeoutWatcher(requestId, bestDriverId, const Duration(seconds: 14));
  }

  // ─────────────────────────────────────────────────────────
  // TIMEOUT WATCHER
  // FIX 5 — stored in map so it can be cancelled on accept
  // ─────────────────────────────────────────────────────────
  void _startTimeoutWatcher(
      String requestId, String driverId, Duration timeout) {
    // Cancel any previous timer for this request
    _timeoutTimers[requestId]?.cancel();

    _timeoutTimers[requestId] = Timer(timeout, () async {
      _timeoutTimers.remove(requestId);
      try {
        final reqRef  = _firestore.collection('emergency_requests').doc(requestId);
        final reqSnap = await reqRef.get();
        if (!reqSnap.exists) return;

        final data     = reqSnap.data()!;
        final status   = data['status']            as String? ?? '';
        final assigned = data['assignedAmbulance'] as String? ?? '';

        // FIX 5 — only reassign if still waiting on the SAME driver
        if (status == 'awaiting_driver' && assigned == driverId) {
          await reqRef.update({
            'status'           : 'pending',
            'assignedAmbulance': '',
            'assignedAt'       : null,
          });
          await _assignNearestDriver(requestId);
        }
      } catch (e) {
        debugPrint('Timeout watcher error: $e'); // FIX 1
      }
    });
  }

  // ─────────────────────────────────────────────────────────
  // DRIVER ACCEPT
  // FIX 4+5 — cancel timeout timer + error handling between writes
  // ─────────────────────────────────────────────────────────
  Future<void> handleDriverAccept(String requestId, String driverId) async {
    final reqRef  = _firestore.collection('emergency_requests').doc(requestId);
    final reqSnap = await reqRef.get();
    if (!reqSnap.exists) return;

    final data     = reqSnap.data()!;
    final assigned = data['assignedAmbulance'] as String? ?? '';
    if (assigned != driverId) return; // reassigned to someone else already

    // FIX 5 — cancel the timeout so it doesn't fire after accept
    _timeoutTimers[requestId]?.cancel();
    _timeoutTimers.remove(requestId);

    // FIX 4 — wrap both writes; if first fails, second won't corrupt state
    try {
      await reqRef.update({
        'status'           : 'assigned',
        'assignedAmbulance': driverId,
        'assignedAt'       : FieldValue.serverTimestamp(),
      });

      await _firestore.collection('ambulances').doc(driverId).update({
        'status'   : 'busy',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('handleDriverAccept error: $e');
      rethrow; // let the UI show the error
    }
  }

  // ─────────────────────────────────────────────────────────
  // DRIVER REJECT
  // ─────────────────────────────────────────────────────────
  Future<void> handleDriverReject(String requestId, String driverId) async {
    // Cancel timeout — we're handling rejection manually now
    _timeoutTimers[requestId]?.cancel();
    _timeoutTimers.remove(requestId);

    final reqRef  = _firestore.collection('emergency_requests').doc(requestId);
    final reqSnap = await reqRef.get();
    if (!reqSnap.exists) return;

    final data     = reqSnap.data()!;
    final assigned = data['assignedAmbulance'] as String? ?? '';
    if (assigned != driverId) return;

    try {
      await reqRef.update({
        'assignedAmbulance': '',
        'status'           : 'pending',
        'assignedAt'       : null,
      });
      await _assignNearestDriver(requestId);
    } catch (e) {
      debugPrint('handleDriverReject error: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────
  // HAVERSINE DISTANCE (metres)
  // ─────────────────────────────────────────────────────────
  double _haversineDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const R    = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a    = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _degToRad(double deg) => deg * pi / 180.0;
}