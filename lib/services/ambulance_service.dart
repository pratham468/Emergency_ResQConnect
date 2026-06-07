import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';


class AmbulanceService {
final _firestore = FirebaseFirestore.instance;
Timer? _timer;


Future<void> updateDriverStatus(String driverId, String status) async {
await _firestore.collection('ambulances').doc(driverId).set({
'driverId': driverId,
'status': status,
'updatedAt': FieldValue.serverTimestamp(),
}, SetOptions(merge: true));
}


Future<void> updateDriverLocation(String driverId, Position pos) async {
await _firestore.collection('ambulances').doc(driverId).set({
'driverId': driverId,
'currentLocation': {'lat': pos.latitude, 'lng': pos.longitude},
'updatedAt': FieldValue.serverTimestamp(),
}, SetOptions(merge: true));
}


/// Start periodic location updates (call when driver app is active)
void startLocationUpdates({Duration interval = const Duration(seconds: 3)}) async {
final user = FirebaseAuth.instance.currentUser;
if (user == null) return;
final driverId = user.uid;


// ensure permission handled in UI before calling this
_timer?.cancel();
_timer = Timer.periodic(interval, (_) async {
try {
final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
await updateDriverLocation(driverId, pos);
} catch (e) {
// optionally log
}
});
await updateDriverStatus(driverId, 'available');
}


void stopLocationUpdates() async {
_timer?.cancel();
final user = FirebaseAuth.instance.currentUser;
if (user != null) {
await updateDriverStatus(user.uid, 'offline');
}
}
}