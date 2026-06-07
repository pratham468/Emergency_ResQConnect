import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// -------------------------
  /// LOGIN USER 
  /// -------------------------
  Future<String> loginUser(String email, String password) async {
    try {
      if (email.isEmpty || password.isEmpty) {
        return "error";
      }

      // Sign in
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final String uid = userCredential.user!.uid;

      // Fetch user document
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(uid).get();

      if (!userDoc.exists) return "error";

      String role = (userDoc['role'] ?? '').toString().toLowerCase();

      // Save FCM token after login
      try {
        String? token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await _firestore.collection('users').doc(uid).update({
            'fcmToken': token,
          });
        }
      } catch (e) {
        print("FCM token error: $e");
      }

      // Normalize role
      if (role == "user") return "user";
      if (role == "ambulance driver") return "driver";
      if (role == "blood bank manager") return "manager";

      return "error";

    } on FirebaseAuthException catch (e) {
      print("Auth Error: ${e.code} - ${e.message}");
      return "error";
    } catch (e) {
      print("Error: $e");
      return "error";
    }
  }

  /// -------------------------
  /// REGISTER USER
  /// -------------------------
  Future<bool> registerUser(
      String email, String password, String name, String role) async {
    try {
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final String uid = userCredential.user!.uid;

      // Get FCM token on register
      String? token = await FirebaseMessaging.instance.getToken();

      await _firestore.collection('users').doc(uid).set({
        'uid': uid,
        'name': name,
        'email': email,
        'role': role,
        'fcmToken': token ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // If new account is ambulance driver → create ambulance record
      if (role.toLowerCase() == "ambulance driver") {
        await _firestore.collection('ambulances').doc(uid).set({
          'driverId': uid,
          'driverName': name,
          'status': 'offline',
          'currentLocation': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      return true;

    } on FirebaseAuthException catch (e) {
      print("Registration Error: ${e.code} - ${e.message}");
      return false;
    } catch (e) {
      print("Error: $e");
      return false;
    }
  }

  /// -------------------------
  /// LOGOUT
  /// -------------------------
  Future<void> logout() async {
    final uid = _auth.currentUser?.uid;

    // Optional: Mark driver offline on logout
    if (uid != null) {
      final userDoc =
          await _firestore.collection('users').doc(uid).get();

      if (userDoc.exists &&
          (userDoc['role'] ?? '').toString().toLowerCase() ==
              "ambulance driver") {
        await _firestore.collection('ambulances').doc(uid).update({
          'status': 'offline',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    await _auth.signOut();
  }
}
