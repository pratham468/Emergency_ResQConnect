import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'driver_incoming_request.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  String _status = 'offline';
  String _driverName = '';
  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  // ----------------------------------------
  // LOAD STATUS + NAME FROM FIRESTORE
  // ----------------------------------------
  Future<void> _loadInitialData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // Fetch ambulance doc for status
      final ambDoc =
          await _firestore.collection('ambulances').doc(user.uid).get();
      if (ambDoc.exists && mounted) {
        setState(() {
          _status = (ambDoc.data()?['status'] as String?) ?? 'offline';
        });
        // Resume location updates if was available before app restart
        if (_status == 'available') {
          _startLocationUpdates(user.uid);
        }
      }

      // Fetch driver name from users or drivers collection
      // Change 'drivers' to whichever collection stores your driver profiles
      final userDoc =
          await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && mounted) {
        setState(() {
          // Change 'name' to whatever field key you use in Firestore
          _driverName = userDoc.data()?['name'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Failed to load driver data: $e');
    }
  }

  // ----------------------------------------
  // TOGGLE ONLINE / OFFLINE
  // ----------------------------------------
  Future<void> _toggleAvailability() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final driverId = user.uid;

    if (_status == 'offline') {
      await _firestore.collection('ambulances').doc(driverId).set({
        'status': 'available',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _startLocationUpdates(driverId);
      if (mounted) setState(() => _status = 'available');
    } else {
      _stopLocationUpdates();
      await _firestore.collection('ambulances').doc(driverId).update({
        'status': 'offline',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() => _status = 'offline');
    }
  }

  // ----------------------------------------
  // LOCATION UPDATES
  // ----------------------------------------
  void _startLocationUpdates(String driverId) {
    _updateLocationOnce(driverId);
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _updateLocationOnce(driverId);
    });
  }

  void _stopLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  Future<void> _updateLocationOnce(String driverId) async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      await _firestore.collection('ambulances').doc(driverId).set({
        'currentLocation': {'lat': pos.latitude, 'lng': pos.longitude},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Driver location update failed: $e');
    }
  }

  // ----------------------------------------
  // LOGOUT
  // ----------------------------------------
  Future<void> _logout() async {
    _stopLocationUpdates();
    await _auth.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
  }

  @override
  void dispose() {
    _stopLocationUpdates();
    super.dispose();
  }

  // ----------------------------------------
  // HELPERS
  // ----------------------------------------
  bool get _isOnline => _status == 'available' || _status == 'busy';

  Color get _statusColor {
    switch (_status) {
      case 'available':
        return Colors.green;
      case 'busy':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String get _statusLabel {
    switch (_status) {
      case 'available':
        return 'Online — Available';
      case 'busy':
        return 'Online — On a trip';
      default:
        return 'Offline';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final driverId = user?.uid ?? '';
    final displayName = _driverName.isNotEmpty
        ? _driverName
        : (user?.email ?? '');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── PROFILE CARD ──────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.redAccent.shade100,
                      child: Text(
                        _driverName.isNotEmpty
                            ? _driverName[0].toUpperCase()
                            : 'D',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Welcome back,',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── STATUS CARD ───────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _statusLabel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: _statusColor,
                      ),
                    ),
                    const Spacer(),
                    // Toggle switch
                    Transform.scale(
                      scale: 0.85,
                      child: Switch(
                        value: _isOnline,
                        activeColor: Colors.green,
                        // Disable toggle when busy (on a trip)
                        onChanged: _status == 'busy'
                            ? null
                            : (_) => _toggleAvailability(),
                      ),
                    ),
                  ],
                ),
              ),

              if (_status == 'busy')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'You cannot go offline while on a trip.',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                  ),
                ),

              const SizedBox(height: 28),

              const Text(
                'Actions',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                  letterSpacing: 0.4,
                ),
              ),

              const SizedBox(height: 12),

              // ── VIEW REQUESTS BUTTON ──────────────────────
              _ActionTile(
                icon: Icons.notifications_active,
                iconColor: Colors.redAccent,
                label: 'Incoming Requests',
                description: 'View and respond to emergency requests',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DriverIncomingRequest(driverId: driverId),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── LOCATION STATUS ───────────────────────────
              _ActionTile(
                icon: Icons.location_on,
                iconColor: Colors.blue,
                label: 'Location Sharing',
                description: _isOnline
                    ? 'Sharing your location every 3 seconds'
                    : 'Go online to start sharing location',
                onTap: null,
                trailing: _isOnline
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Text(
                          'Active',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade700,
                          ),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          'Off',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
              ),

              const SizedBox(height: 28),

              // ── INFO STRIP ────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline, color: Colors.blueAccent, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Go online to receive emergency requests from nearby users.',
                        style: TextStyle(fontSize: 13, color: Colors.blueAccent),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────
// REUSABLE ACTION TILE
// ────────────────────────────────────────────────────────
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String description;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.description,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        )),
                    const SizedBox(height: 3),
                    Text(description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        )),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  (onTap != null
                      ? Icon(Icons.chevron_right,
                          color: Colors.grey.shade400)
                      : const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }
}