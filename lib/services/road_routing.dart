import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:latlong2/latlong.dart';

class RouteDestination {
  const RouteDestination(this.label, this.point);
  final String label;
  final LatLng point;
}

class RoadRoute {
  const RoadRoute({
    required this.points,
    required this.distance,
    required this.duration,
    required this.directions,
  });
  final List<LatLng> points;
  final double distance, duration;
  final List<String> directions;

  factory RoadRoute.fromJson(Map<String, dynamic> data) {
    final routes = data['routes'];
    if (data['code'] != 'Ok' || routes is! List || routes.isEmpty) {
      throw StateError(
        'No driving route was found. Confirm the destination pin and try again.',
      );
    }
    final route = routes.first as Map;
    final geometry = route['geometry'] as Map?;
    final coordinates = geometry?['coordinates'];
    if (geometry?['type'] != 'LineString' ||
        coordinates is! List ||
        coordinates.length < 2) {
      throw const FormatException('Missing road geometry.');
    }
    final distance = route['distance'];
    final duration = route['duration'];
    if (distance is! num ||
        duration is! num ||
        !distance.isFinite ||
        !duration.isFinite ||
        distance < 0 ||
        duration < 0) {
      throw const FormatException('Invalid route measurements.');
    }
    final points = coordinates
        .map<LatLng>((point) => readRoutePoint(point))
        .toList(growable: false);
    final directions = <String>[];
    for (final leg in (route['legs'] as List? ?? [])) {
      for (final step in (leg['steps'] as List? ?? [])) {
        final maneuver = step['maneuver'] as Map? ?? {};
        final type = '${maneuver['type'] ?? 'Continue'}'.replaceAll('_', ' ');
        final modifier = '${maneuver['modifier'] ?? ''}';
        final name = '${step['name'] ?? ''}';
        final exit = maneuver['exit'];
        final instruction = [
          type,
          if (modifier.isNotEmpty) modifier,
          if (exit != null) 'exit $exit',
          if (name.isNotEmpty) 'onto $name',
        ].join(' ');
        final meters = step['distance'];
        directions.add(
          '${instruction[0].toUpperCase()}${instruction.substring(1)}${meters is num ? ' (${meters.round()} m)' : ''}',
        );
      }
    }
    return RoadRoute(
      points: points,
      distance: distance.toDouble(),
      duration: duration.toDouble(),
      directions: directions,
    );
  }
}

LatLng readRoutePoint(dynamic value) {
  if (value is! List ||
      value.length < 2 ||
      value[0] is! num ||
      value[1] is! num) {
    throw const FormatException('Invalid route coordinate.');
  }
  final longitude = (value[0] as num).toDouble(),
      latitude = (value[1] as num).toDouble();
  if (!latitude.isFinite ||
      !longitude.isFinite ||
      latitude.abs() > 90 ||
      longitude.abs() > 180) {
    throw const FormatException('Invalid route coordinate.');
  }
  return LatLng(latitude, longitude);
}

/// Uses a separate HTTP client so account credentials never reach map providers.
class RoadRouting {
  RoadRouting({Dio? client, String? routingUrl, String? geocodingUrl})
    : _client =
          client ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            ),
          ),
      _ownsClient = client == null,
      _routingUrl =
          routingUrl ??
          _setting('ROUTING_URL', 'https://router.project-osrm.org'),
      _geocodingUrl =
          geocodingUrl ?? _setting('GEOCODING_URL', 'https://photon.komoot.io');
  final Dio _client;
  final bool _ownsClient;
  final String _routingUrl, _geocodingUrl;
  final Map<String, List<RouteDestination>> _destinations = {};

  static String _setting(String key, String fallback) =>
      dotenv.isInitialized ? dotenv.env[key] ?? fallback : fallback;
  String _endpoint(String base, String path) =>
      '${base.replaceFirst(RegExp(r'/+$'), '')}$path';

  Future<List<RouteDestination>> search(
    String address, {
    LatLng? near,
    CancelToken? cancelToken,
  }) async {
    final query = address.trim();
    if (query.isEmpty) return [];
    final cached = _destinations[query];
    if (cached != null) return cached;
    final response = await _client.get(
      _endpoint(_geocodingUrl, '/api/'),
      queryParameters: {
        'q': query,
        'limit': 5,
        'lang': 'en',
        'countrycode': 'PH',
        if (near != null) 'lat': near.latitude,
        if (near != null) 'lon': near.longitude,
      },
      cancelToken: cancelToken,
    );
    final features = response.data is Map ? response.data['features'] : null;
    if (features is! List) {
      throw const FormatException('Invalid address search response.');
    }
    final results = <RouteDestination>[];
    for (final feature in features) {
      if (feature is! Map ||
          feature['geometry'] is! Map ||
          feature['properties'] is! Map) {
        continue;
      }
      final geometry = feature['geometry'] as Map;
      if (geometry['type'] != 'Point') continue;
      final properties = feature['properties'] as Map;
      try {
        final point = readRoutePoint(geometry['coordinates']);
        final label =
            [
                  'name',
                  'housenumber',
                  'street',
                  'district',
                  'city',
                  'state',
                  'country',
                ]
                .map((key) => properties[key]?.toString() ?? '')
                .where((value) => value.isNotEmpty)
                .toSet()
                .join(', ');
        results.add(RouteDestination(label.isEmpty ? query : label, point));
      } on FormatException {
        continue;
      }
    }
    if (results.isNotEmpty) _destinations[query] = results;
    return results;
  }

  Future<RoadRoute> route(
    LatLng origin,
    LatLng destination, {
    CancelToken? cancelToken,
  }) async {
    final coordinates =
        '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}';
    final response = await _client.get(
      _endpoint(_routingUrl, '/route/v1/driving/$coordinates'),
      queryParameters: {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'true',
        'alternatives': 'false',
        'radiuses': '100;100',
      },
      cancelToken: cancelToken,
    );
    if (response.data is! Map) {
      throw const FormatException('Invalid route response.');
    }
    return RoadRoute.fromJson(Map<String, dynamic>.from(response.data));
  }

  void dispose() {
    if (_ownsClient) _client.close(force: true);
  }
}
