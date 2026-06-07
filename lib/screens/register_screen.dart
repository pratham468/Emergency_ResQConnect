import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';

import 'location_picker_screen.dart'; // adjust import path to match your project

class RegisterScreen extends StatefulWidget {
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name        = TextEditingController();
  final _email       = TextEditingController();
  final _password    = TextEditingController();
  final _phone       = TextEditingController();
  final _ambulanceNo = TextEditingController();
  final _address     = TextEditingController();

  String   role    = "User";
  bool     loading = false;

  // Picked from the map — null until manager taps "Pick Location"
  LatLng?  _pickedLocation;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _ambulanceNo.dispose();
    _address.dispose();
    super.dispose();
  }

  // ── Open map and wait for the manager to pick a pin ─────────────────────
  Future<void> _openLocationPicker() async {
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initialLocation: _pickedLocation),
      ),
    );
    if (result != null) {
      setState(() => _pickedLocation = result);
    }
  }

  // ── Registration logic ───────────────────────────────────────────────────
  Future<void> register() async {
    if (_email.text.trim().isEmpty || _password.text.trim().isEmpty) {
      _showSnack("Email and password are required.");
      return;
    }

    if (_name.text.trim().isEmpty) {
      _showSnack("Name is required.");
      return;
    }

    if (role == "Blood Bank Manager") {
      if (_address.text.trim().isEmpty) {
        _showSnack("Please enter the blood bank address.");
        return;
      }
      if (_pickedLocation == null) {
        _showSnack("Please pick your blood bank location on the map.");
        return;
      }
    }

    setState(() => loading = true);

    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        
        email:    _email.text.trim(),
        password: _password.text.trim(),
      );
      final uid = cred.user!.uid;

      // Common users collection
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        "uid":       uid,
        "name":      _name.text.trim(),
        "email":     _email.text.trim(),
        "role":      role,
        "createdAt": FieldValue.serverTimestamp(),
      });

      // Ambulance Driver
      if (role == "Ambulance Driver") {
        await FirebaseFirestore.instance.collection('ambulances').doc(uid).set({
          "driverId":        uid,
          "name":            _name.text.trim(),
          "email":           _email.text.trim(),
          "phone":           _phone.text.trim(),
          "ambulanceNo":     _ambulanceNo.text.trim(),
          "status":          "offline",
          "currentLocation": null,
        });
      }

      // Blood Bank Manager
      if (role == "Blood Bank Manager") {
        await FirebaseFirestore.instance.collection('blood_banks').doc(uid).set({
          "uid":       uid,
          "name":      _name.text.trim(),
          "email":     _email.text.trim(),
          "address":   _address.text.trim(),
          "location":  GeoPoint(_pickedLocation!.latitude, _pickedLocation!.longitude),
          "createdAt": FieldValue.serverTimestamp(),
        });
      }

      _showSnack("Registered Successfully");
      Navigator.pushReplacementNamed(context, '/');
    } catch (e) {
      _showSnack("Error: $e");
    }

    setState(() => loading = false);
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  InputDecoration _inputStyle(String label, IconData icon) => InputDecoration(
        labelText:  label,
        prefixIcon: Icon(icon, color: Colors.deepPurple),
        border:     OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   const BorderSide(color: Colors.deepPurple, width: 2),
        ),
      );

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDriver    = role == "Ambulance Driver";
    final isBloodBank = role == "Blood Bank Manager";
    

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title:           const Text("Register"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ── Role Dropdown ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple.shade200),
                color:  Colors.white,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value:      role,
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.deepPurple),
                  items: ["User", "Ambulance Driver", "Blood Bank Manager"]
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) => setState(() {
                    role = val!;
                    _pickedLocation = null; // reset when role changes
                  }),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Name ─────────────────────────────────────────────────────────
           
                  TextField(
                    controller: _name,
                    decoration: _inputStyle("Full Name", Icons.person),
                  ),
                  const SizedBox(height: 12),


            // ── Email ─────────────────────────────────────────────────────────
            TextField(
              controller:   _email,
              keyboardType: TextInputType.emailAddress,
              decoration:   _inputStyle("Email", Icons.email),
            ),
            const SizedBox(height: 12),

            // ── Password ──────────────────────────────────────────────────────
            TextField(
              controller:  _password,
              obscureText: true,
              decoration:  _inputStyle("Password (min 6 chars)", Icons.lock),
            ),
            const SizedBox(height: 12),

            // ── Ambulance Driver extras ───────────────────────────────────────
            if (isDriver) ...[
              TextField(
                controller:   _phone,
                keyboardType: TextInputType.phone,
                decoration:   _inputStyle("Phone Number", Icons.phone),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ambulanceNo,
                decoration: _inputStyle("Ambulance Number", Icons.local_hospital),
              ),
              const SizedBox(height: 12),
            ],

            // ── Blood Bank Manager extras ─────────────────────────────────────
            if (isBloodBank) ...[
              // Address text field
              TextField(
                controller: _address,
                maxLines:   2,
                decoration: _inputStyle("Blood Bank Address", Icons.location_on),
              ),
              const SizedBox(height: 12),

              // Map location picker button
              OutlinedButton.icon(
                onPressed: _openLocationPicker,
                icon: const Icon(Icons.map, color: Colors.deepPurple),
                label: Text(
                  _pickedLocation == null
                      ? "Pick Location on Map"
                      : "Location Selected  ✓  (tap to change)",
                  style: const TextStyle(color: Colors.deepPurple),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side:    const BorderSide(color: Colors.deepPurple),
                  shape:   RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),

              // Show coordinates preview after picking
              if (_pickedLocation != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color:        Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border:       Border.all(color: Colors.deepPurple.shade100),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.my_location, color: Colors.deepPurple, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        "Lat: ${_pickedLocation!.latitude.toStringAsFixed(5)}"
                        "   Lng: ${_pickedLocation!.longitude.toStringAsFixed(5)}",
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),
            ],

            const SizedBox(height: 8),

            // ── Register Button ───────────────────────────────────────────────
            loading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text(
                      "Register",
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),

            const SizedBox(height: 10),

            TextButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/'),
              child: const Text("Already have an account? Login"),
            ),
          ],
        ),
      ),
    );
  }
}