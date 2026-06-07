import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'user_tracking_screen.dart';
import 'location_confirm_screen.dart';
import '../services/emergency_service.dart';
import 'package:emergency_blood_bank/screens/search_result_screen.dart';
import 'history_screen.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({Key? key}) : super(key: key);

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  bool _loadingAmbulance = false;
  bool _loadingBlood = false;
  String _userName = '';

  final EmergencyService _service = EmergencyService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _fetchUserName();
  }

  Future<void> _fetchUserName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && mounted) {
        setState(() => _userName = doc.data()?['name'] ?? '');
      }
    } catch (e) {
      debugPrint('Failed to fetch user name: $e');
    }
  }

  // 🚑 AMBULANCE
  Future<void> _sendEmergency() async {
    setState(() => _loadingAmbulance = true);

    try {
      double lat;
      double lng;

      if (kIsWeb) {
        final confirmed = await Navigator.push<LatLng?>(
          context,
          MaterialPageRoute(
              builder: (_) => const LocationConfirmScreen()),
        );

        if (confirmed == null) {
          setState(() => _loadingAmbulance = false);
          return;
        }

        lat = confirmed.latitude;
        lng = confirmed.longitude;
      } else {
        final pos = await Geolocator.getCurrentPosition();
        lat = pos.latitude;
        lng = pos.longitude;
      }

      final requestId =
          await _service.createEmergencyRequest(lat: lat, lng: lng);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UserTrackingScreen(requestId: requestId),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }

    setState(() => _loadingAmbulance = false);
  }

  // 🩸 BLOOD REQUEST
  Future<void> _requestBlood() async {
    final groupController = TextEditingController();
    final unitController = TextEditingController();

    final result = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Request Blood"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: groupController,
              decoration:
                  const InputDecoration(labelText: "Blood Group (A+)"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: unitController,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: "Units Required"),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              final group = groupController.text.trim().toUpperCase();
              final units =
                  int.tryParse(unitController.text.trim()) ?? 0;

              if (group.isEmpty || units <= 0) return;

              Navigator.pop(context, {
                'group': group,
                'units': units,
              });
            },
            child: const Text("Search"),
          ),
        ],
      ),
    );

    if (result == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchResultScreen(
          bloodGroup: result['group'],
          units: result['units'],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _userName.isNotEmpty
        ? _userName
        : (FirebaseAuth.instance.currentUser?.email ?? '');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // PROFILE CARD
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.redAccent.shade100,
                      child: Text(
                        _userName.isNotEmpty
                            ? _userName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(displayName,
                        style: const TextStyle(fontSize: 18)),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              const Text("Quick Actions"),

              const SizedBox(height: 15),

              // 🚑 Ambulance
              _ActionButton(
                label: 'Request Ambulance',
                description: 'Get nearest ambulance',
                icon: Icons.emergency,
                color: Colors.redAccent,
                loading: _loadingAmbulance,
                onTap: _sendEmergency,
              ),

              const SizedBox(height: 15),

              // 🩸 Blood
              _ActionButton(
                label: 'Request Blood',
                description: 'Find blood banks near you',
                icon: Icons.bloodtype,
                color: Colors.red,
                loading: _loadingBlood,
                onTap: _requestBlood,
              ),

              const SizedBox(height: 15),

              // 📜 HISTORY
              _ActionButton(
                label: 'History',
                description: 'View all your requests',
                icon: Icons.history,
                color: Colors.blue,
                loading: false,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const HistoryScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// BUTTON UI
class _ActionButton extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(description),
                ],
              ),
            ),
            loading
                ? const CircularProgressIndicator()
                : const Icon(Icons.arrow_forward),
          ],
        ),
      ),
    );
  }
}