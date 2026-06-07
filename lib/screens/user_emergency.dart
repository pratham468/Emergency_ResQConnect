import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/emergency_service.dart';


class UserEmergencyScreen extends StatefulWidget {
const UserEmergencyScreen({Key? key}) : super(key: key);


@override
State<UserEmergencyScreen> createState() => _UserEmergencyScreenState();
}


class _UserEmergencyScreenState extends State<UserEmergencyScreen> {
bool _loading = false;
String? _requestId;
final _service = EmergencyService();


Future<void> _sendRequest() async {
setState(() => _loading = true);
try {
LocationPermission permission = await Geolocator.checkPermission();
if (permission == LocationPermission.denied) {
permission = await Geolocator.requestPermission();
}
final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

