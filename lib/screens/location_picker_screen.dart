import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class LocationPickerScreen extends StatefulWidget {
  /// Pre-selected location (optional). Falls back to a sensible default.
  final LatLng? initialLocation;

  const LocationPickerScreen({Key? key, this.initialLocation}) : super(key: key);

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  // Default center: India (adjust as needed)
  static const LatLng _defaultCenter = LatLng(20.5937, 78.9629);

  late LatLng _pickedLocation;
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _pickedLocation  = widget.initialLocation ?? _defaultCenter;
    _mapController   = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _onMapTap(TapPosition _, LatLng point) {
    setState(() => _pickedLocation = point);
  }

  void _confirm() {
    Navigator.of(context).pop(_pickedLocation);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pick Blood Bank Location"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _confirm,
            icon:  const Icon(Icons.check, color: Colors.white),
            label: const Text("Confirm", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Flutter Map ────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pickedLocation,
              initialZoom:   13,
              onTap:         _onMapTap,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all, // enable pinch, scroll zoom, drag
                scrollWheelVelocity: 0.005, // smooth scroll wheel zoom on web
              ),
            ),
            children: [
              // Tile layer (OpenStreetMap — no API key needed)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.emergency_blood_bank',
              ),

              // Pin marker at picked location
              MarkerLayer(
                markers: [
                  Marker(
                    point:  _pickedLocation,
                    width:  60,
                    height: 60,
                    child: const Icon(
                      Icons.location_pin,
                      size:  50,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ── Instruction card ───────────────────────────────────────────────
          Positioned(
            top:   12,
            left:  16,
            right: 16,
            child: Card(
              color:  Colors.white.withOpacity(0.92),
              shape:  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child:  const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.touch_app, color: Colors.deepPurple),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Tap anywhere on the map to place the pin at your blood bank location.",
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Coordinates chip ───────────────────────────────────────────────
          Positioned(
            bottom: 90,
            left:   16,
            right:  16,
            child: Card(
              color:  Colors.white.withOpacity(0.92),
              shape:  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child:  Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.my_location, color: Colors.deepPurple, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      "Lat: ${_pickedLocation.latitude.toStringAsFixed(5)}"
                      "   Lng: ${_pickedLocation.longitude.toStringAsFixed(5)}",
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Confirm FAB ────────────────────────────────────────────────────
          Positioned(
            bottom: 24,
            left:   40,
            right:  40,
            child: ElevatedButton.icon(
              onPressed: _confirm,
              icon:  const Icon(Icons.check_circle_outline),
              label: const Text("Confirm This Location", style: TextStyle(fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape:  RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}