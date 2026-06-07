import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:geolocator/geolocator.dart';

import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/user_dashboard.dart';
import 'screens/driver_dashboard.dart';
import 'screens/manager_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 🔥 IMPORTANT: Ask for location permission on real devices
  await Geolocator.requestPermission();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emergency Blood Bank',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.red,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => LoginScreen(),
        '/register': (context) => RegisterScreen(),
        '/userDashboard': (context) => UserDashboard(),
        '/driverDashboard': (context) => DriverDashboard(),
        '/managerDashboard': (context) => ManagerDashboard(),
      },
    );
  }
}
