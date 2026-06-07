import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/emergency_service.dart';
import 'driver_navigation_screen.dart';

class DriverIncomingRequest extends StatefulWidget {
  final String driverId;

  const DriverIncomingRequest({required this.driverId, super.key});

  @override
  State<DriverIncomingRequest> createState() => _DriverIncomingRequestState();
}

class _DriverIncomingRequestState extends State<DriverIncomingRequest> {
  final _firestore = FirebaseFirestore.instance;
  final EmergencyService _service = EmergencyService();

  bool _accepting = false;
  bool _rejecting = false;

  // FIX 5 — countdown matching the 14s timeout in emergency_service.dart
  int _secondsLeft = 14;
  Timer? _countdownTimer;
  String? _currentRequestId; // track which request the timer is for

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  // Start countdown when a new request arrives
  void _startCountdown(String requestId) {
    if (_currentRequestId == requestId) return; // already running for this request
    _currentRequestId = requestId;

    _countdownTimer?.cancel();
    _secondsLeft = 14;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) t.cancel();
    });
  }

  // ─────────────────────────────────────────────────────────
  // ACCEPT
  // FIX 1+2: use already-fetched userLoc from snapshot,
  //           add mounted guard, add loading state
  // ─────────────────────────────────────────────────────────
  Future<void> _accept(String requestId, Map userLoc) async {
    if (_accepting) return;
    setState(() => _accepting = true);
    _countdownTimer?.cancel();

    try {
      await _service.handleDriverAccept(requestId, widget.driverId);

      if (!mounted) return;

      // FIX 2 — userLoc already available from stream snapshot, no extra fetch needed
      final userLat = (userLoc['lat'] as num).toDouble();
      final userLng = (userLoc['lng'] as num).toDouble();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DriverNavigationScreen(
            requestId: requestId,
            driverId: widget.driverId,
            userLat: userLat,
            userLng: userLng,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _accepting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept: $e')),
      );
    }
  }

  // ─────────────────────────────────────────────────────────
  // REJECT
  // FIX 6: stay on screen after reject so next assignment shows up
  // ─────────────────────────────────────────────────────────
  Future<void> _reject(String requestId) async {
    if (_rejecting) return;
    setState(() => _rejecting = true);
    _countdownTimer?.cancel();

    try {
      await _service.handleDriverReject(requestId, widget.driverId);
    } catch (e) {
      debugPrint('Reject error: $e');
    }

    if (!mounted) return;
    // FIX 6 — reset state and stay on screen; stream will show next request
    setState(() {
      _rejecting = false;
      _currentRequestId = null;
      _secondsLeft = 14;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Incoming Request'),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('emergency_requests')
            .where('assignedAmbulance', isEqualTo: widget.driverId)
            .where('status', isEqualTo: 'awaiting_driver')
            .snapshots(),
        builder: (context, snap) {

          // ── NO REQUEST ──────────────────────────────────
          if (!snap.hasData ||
              snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.redAccent),
            );
          }

          if (snap.data!.docs.isEmpty) {
            _countdownTimer?.cancel();
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_none,
                      size: 72, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text(
                    'No incoming requests',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You will be notified when a nearby\nemergency is assigned to you.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          // ── REQUEST FOUND ───────────────────────────────
          final req       = snap.data!.docs.first;
          final requestId = req['requestId'] as String;
          final userLoc   = req['userLocation'] as Map;
          final userLat   = (userLoc['lat'] as num).toDouble();
          final userLng   = (userLoc['lng'] as num).toDouble();

          // Start countdown for this request
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _startCountdown(requestId));

          // Countdown colour: green → orange → red
          final Color timerColor = _secondsLeft > 9
              ? Colors.green
              : _secondsLeft > 4
                  ? Colors.orange
                  : Colors.red;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  // ── ALERT HEADER ────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.emergency,
                            color: Colors.redAccent, size: 28),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Emergency Request!',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.redAccent),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'A patient needs immediate assistance',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),

                        // FIX 5 — countdown circle
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CircularProgressIndicator(
                                value: _secondsLeft / 14,
                                strokeWidth: 4,
                                backgroundColor: Colors.grey.shade200,
                                color: timerColor,
                              ),
                              Center(
                                child: Text(
                                  '$_secondsLeft',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: timerColor),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── LOCATION CARD ────────────────────────
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Patient Location',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54),
                        ),
                        const SizedBox(height: 14),
                        _InfoRow(
                          icon: Icons.location_on,
                          iconColor: Colors.redAccent,
                          label: 'Latitude',
                          // FIX 4 — show 5 decimal places, cleaner than raw double
                          value: userLat.toStringAsFixed(5),
                        ),
                        const Divider(height: 20),
                        _InfoRow(
                          icon: Icons.location_on,
                          iconColor: Colors.redAccent,
                          label: 'Longitude',
                          value: userLng.toStringAsFixed(5),
                        ),
                        const Divider(height: 20),
                        _InfoRow(
                          icon: Icons.tag,
                          iconColor: Colors.blueAccent,
                          label: 'Request ID',
                          value: requestId.length > 12
                              ? '${requestId.substring(0, 12)}…'
                              : requestId,
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // ── REJECT BUTTON ────────────────────────
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: (_rejecting || _accepting)
                          ? null
                          : () => _reject(requestId),
                      icon: _rejecting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.grey),
                            )
                          : const Icon(Icons.close, color: Colors.grey),
                      label: const Text('Reject',
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.grey),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── ACCEPT BUTTON ────────────────────────
                  SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: (_accepting || _rejecting)
                          ? null
                          : () => _accept(requestId, userLoc),
                      icon: _accepting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(
                        _accepting ? 'Accepting…' : 'Accept Request',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.green.shade200,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// REUSABLE INFO ROW
// ─────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87)),
            ],
          ),
        ),
      ],
    );
  }
}