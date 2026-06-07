import 'package:firebase_messaging/firebase_messaging.dart';


class FcmService {
final _messaging = FirebaseMessaging.instance;


Future<void> init() async {
// request permission
await _messaging.requestPermission();


// get token (store this in user doc to send messages from server)
final token = await _messaging.getToken();
print('FCM token: $token');
}


/// Use Cloud Functions or server with server key to send push to token stored in user doc
}