import 'dart:math';


/// Returns distance in meters between two coordinates
double haversineDistanceMeters(double lat1, double lng1, double lat2, double lng2) {
const R = 6371000.0; // Earth radius in meters
final phi1 = lat1 * pi / 180.0;
final phi2 = lat2 * pi / 180.0;
final dPhi = (lat2 - lat1) * pi / 180.0;
final dLambda = (lng2 - lng1) * pi / 180.0;


final a = sin(dPhi / 2) * sin(dPhi / 2) +
cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2);
final c = 2 * atan2(sqrt(a), sqrt(1 - a));
return R * c;
}