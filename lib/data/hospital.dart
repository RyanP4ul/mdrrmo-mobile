import 'package:latlong2/latlong.dart';

import 'input_validation.dart';

class HospitalRecommendation {
  const HospitalRecommendation({
    required this.id,
    required this.name,
    required this.address,
    required this.point,
    required this.distanceKm,
    this.availableBeds,
    this.contact,
    this.specialtyMatch = false,
  });

  final int id;
  final String name, address;
  final LatLng point;
  final double distanceKm;
  final int? availableBeds;
  final String? contact;
  final bool specialtyMatch;

  factory HospitalRecommendation.fromJson(Map<String, dynamic> data) {
    final lat = (data['lat'] as num).toDouble();
    final lng = (data['lng'] as num).toDouble();
    final distance = (data['distance'] as num).toDouble();
    if (InputValidation.coordinates(lat, lng) != null ||
        !distance.isFinite ||
        distance < 0) {
      throw const FormatException('Invalid hospital location.');
    }
    return HospitalRecommendation(
      id: data['id'] as int,
      name: data['name'] as String,
      address: data['address'] as String,
      point: LatLng(lat, lng),
      distanceKm: distance,
      availableBeds: data['availableBeds'] as int?,
      contact: data['contactNumber'] as String?,
      specialtyMatch: data['match'] == true,
    );
  }
}
