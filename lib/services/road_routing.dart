import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:latlong2/latlong.dart';

class RouteDestination {
  const RouteDestination(this.label, this.point);
  final String label;
  final LatLng point;
}

class RouteStep {
  const RouteStep({
    required this.instruction,
    required this.maneuverType,
    this.modifier = '',
    this.distanceMeters,
    this.durationSeconds,
    this.startLocation,
    this.endLocation,
  });

  final String instruction;
  final String maneuverType;
  final String modifier;
  final double? distanceMeters;
  final double? durationSeconds;
  final LatLng? startLocation;
  final LatLng? endLocation;
}

class RoadRoute {
  const RoadRoute({
    required this.points,
    required this.distance,
    required this.duration,
    required this.directions,
    this.steps = const [],
  });
  final List<LatLng> points;
  final double distance, duration;
  final List<String> directions;
  final List<RouteStep> steps;

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
    final steps = <RouteStep>[];
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
        final secs = step['duration'];
        final loc = maneuver['location'];
        final startLoc = loc is List && loc.length >= 2
            ? readRoutePoint(loc)
            : null;
        final formattedInstruction =
            '${instruction[0].toUpperCase()}${instruction.substring(1)}';
        steps.add(
          RouteStep(
            instruction: formattedInstruction,
            maneuverType: type.toLowerCase(),
            modifier: modifier.toLowerCase(),
            distanceMeters: meters is num && meters.isFinite
                ? meters.toDouble()
                : null,
            durationSeconds: secs is num && secs.isFinite
                ? secs.toDouble()
                : null,
            startLocation: startLoc,
          ),
        );
        directions.add(
          '$formattedInstruction${meters is num ? ' (${meters.round()} m)' : ''}',
        );
      }
    }
    return RoadRoute(
      points: points,
      distance: distance.toDouble(),
      duration: duration.toDouble(),
      directions: directions,
      steps: steps,
    );
  }

  factory RoadRoute.fromGoogleDirections(Map<String, dynamic> data) {
    final status = data['status']?.toString();
    final routes = data['routes'];
    if (status == 'ZERO_RESULTS' ||
        status == 'NOT_FOUND' ||
        routes is! List ||
        routes.isEmpty) {
      throw StateError(
        'No driving route was found. Confirm the destination pin and try again.',
      );
    }
    if (status != 'OK') {
      throw StateError(
        data['error_message']?.toString() ??
            'Google Directions error: ${status ?? 'unknown'}',
      );
    }
    final route = routes.first as Map;
    final overviewPolyline = route['overview_polyline'] as Map?;
    final encoded = overviewPolyline?['points']?.toString() ?? '';
    final points = decodeGooglePolyline(encoded);
    if (points.length < 2) {
      throw const FormatException('Missing road geometry.');
    }

    double totalDistance = 0;
    double totalDuration = 0;
    final directions = <String>[];
    final steps = <RouteStep>[];

    for (final leg in (route['legs'] as List? ?? [])) {
      if (leg is! Map) continue;
      final legDist = (leg['distance'] as Map?)?['value'];
      final legDur =
          ((leg['duration_in_traffic'] as Map?)?['value']) ??
          ((leg['duration'] as Map?)?['value']);
      if (legDist is num && legDist.isFinite) totalDistance += legDist.toDouble();
      if (legDur is num && legDur.isFinite) totalDuration += legDur.toDouble();

      for (final rawStep in (leg['steps'] as List? ?? [])) {
        if (rawStep is! Map) continue;
        final html = rawStep['html_instructions']?.toString() ?? '';
        final clean = _stripHtml(html);
        final maneuver = rawStep['maneuver']?.toString() ?? '';
        final parsed = _parseGoogleManeuver(maneuver, clean);
        final meters = (rawStep['distance'] as Map?)?['value'];
        final secs = (rawStep['duration'] as Map?)?['value'];
        final startLoc = _readGoogleLatLng(rawStep['start_location']);
        final endLoc = _readGoogleLatLng(rawStep['end_location']);
        final instruction = clean.isEmpty ? 'Continue' : clean;

        steps.add(
          RouteStep(
            instruction: instruction,
            maneuverType: parsed.$1,
            modifier: parsed.$2,
            distanceMeters: meters is num && meters.isFinite
                ? meters.toDouble()
                : null,
            durationSeconds: secs is num && secs.isFinite
                ? secs.toDouble()
                : null,
            startLocation: startLoc,
            endLocation: endLoc,
          ),
        );
        directions.add(
          '$instruction${meters is num ? ' (${meters.round()} m)' : ''}',
        );
      }
    }

    return RoadRoute(
      points: points,
      distance: totalDistance,
      duration: totalDuration,
      directions: directions,
      steps: steps,
    );
  }
}

LatLng? _readGoogleLatLng(dynamic value) {
  if (value is! Map) return null;
  final lat = value['lat'];
  final lng = value['lng'];
  if (lat is! num || lng is! num) return null;
  final dLat = lat.toDouble();
  final dLng = lng.toDouble();
  if (!dLat.isFinite || !dLng.isFinite || dLat.abs() > 90 || dLng.abs() > 180) {
    return null;
  }
  return LatLng(dLat, dLng);
}

String _stripHtml(String html) {
  return html
      .replaceAll(RegExp(r'<div[^>]*>'), ' — ')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

(String, String) _parseGoogleManeuver(String maneuver, String instruction) {
  final m = maneuver.toLowerCase();
  if (m.contains('roundabout') || m.contains('rotary')) {
    return ('roundabout', m.contains('left') ? 'left' : 'right');
  }
  if (m.contains('uturn')) {
    return ('turn', m.contains('right') ? 'uturn right' : 'uturn left');
  }
  if (m.contains('sharp-left')) return ('turn', 'sharp left');
  if (m.contains('sharp-right')) return ('turn', 'sharp right');
  if (m.contains('slight-left') || m.contains('keep-left') || m.contains('fork-left') || m.contains('ramp-left')) {
    return ('turn', 'slight left');
  }
  if (m.contains('slight-right') || m.contains('keep-right') || m.contains('fork-right') || m.contains('ramp-right')) {
    return ('turn', 'slight right');
  }
  if (m.contains('left')) return ('turn', 'left');
  if (m.contains('right')) return ('turn', 'right');
  final lower = instruction.toLowerCase();
  if (lower.contains('destination')) return ('arrive', '');
  return ('continue', 'straight');
}

List<LatLng> decodeGooglePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;
  while (index < encoded.length) {
    var shift = 0;
    var result = 0;
    int byte;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    if (index >= encoded.length) break;
    shift = 0;
    result = 0;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
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
  RoadRouting({
    Dio? client,
    String? routingUrl,
    String? geocodingUrl,
    String? googleApiKey,
  }) : _client =
           client ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 20),
             ),
           ),
       _ownsClient = client == null,
       _customRoutingUrl = routingUrl != null,
       _customGeocodingUrl = geocodingUrl != null,
       _googleApiKey =
           (googleApiKey ??
                   _setting(
                     'GOOGLE_DIRECTIONS_API_KEY',
                     _setting('GOOGLE_MAP_API_KEY', ''),
                   ))
               .trim(),
       _routingUrl =
           routingUrl ??
           _setting('ROUTING_URL', 'https://router.project-osrm.org'),
       _geocodingUrl =
           geocodingUrl ?? _setting('GEOCODING_URL', 'https://photon.komoot.io');
  final Dio _client;
  final bool _ownsClient;
  final bool _customRoutingUrl;
  final bool _customGeocodingUrl;
  final String _googleApiKey;
  final String _routingUrl, _geocodingUrl;
  final Map<String, List<RouteDestination>> _destinations = {};

  static String _setting(String key, String fallback) =>
      dotenv.isInitialized ? dotenv.env[key] ?? fallback : fallback;
  String _endpoint(String base, String path) =>
      '${base.replaceFirst(RegExp(r'/+$'), '')}$path';

  bool get _useGoogleDirections =>
      !_customRoutingUrl && _googleApiKey.isNotEmpty;
  bool get _useGoogleGeocoding =>
      !_customGeocodingUrl && _googleApiKey.isNotEmpty;

  Future<List<RouteDestination>> search(
    String address, {
    LatLng? near,
    CancelToken? cancelToken,
  }) async {
    final query = address.trim();
    if (query.isEmpty) return [];
    final cached = _destinations[query];
    if (cached != null) return cached;

    if (_useGoogleGeocoding) {
      try {
        final results = await _searchGoogle(
          query,
          near: near,
          cancelToken: cancelToken,
        );
        if (results.isNotEmpty) {
          _destinations[query] = results;
          return results;
        }
      } on DioException {
        rethrow;
      } catch (_) {
        // Fall back to Photon geocoding if Google Geocoding API is not enabled.
      }
    }

    final results = await _searchPhoton(
      query,
      near: near,
      cancelToken: cancelToken,
    );
    if (results.isNotEmpty) _destinations[query] = results;
    return results;
  }

  Future<List<RouteDestination>> _searchGoogle(
    String query, {
    LatLng? near,
    CancelToken? cancelToken,
  }) async {
    final response = await _client.get(
      'https://maps.googleapis.com/maps/api/geocode/json',
      queryParameters: {
        'address': query,
        'components': 'country:PH',
        'language': 'en',
        if (near != null)
          'bounds':
              '${near.latitude - 0.25},${near.longitude - 0.25}|${near.latitude + 0.25},${near.longitude + 0.25}',
        'key': _googleApiKey,
      },
      cancelToken: cancelToken,
    );
    if (response.data is! Map) {
      throw const FormatException('Invalid address search response.');
    }
    final status = response.data['status']?.toString();
    if (status == 'ZERO_RESULTS') return [];
    if (status != 'OK') {
      throw StateError('Google Geocoding error: ${status ?? 'unknown'}');
    }
    final items = response.data['results'];
    if (items is! List) return [];
    final results = <RouteDestination>[];
    for (final item in items.take(5)) {
      if (item is! Map) continue;
      final geometry = item['geometry'] as Map?;
      final point = _readGoogleLatLng(geometry?['location']);
      if (point == null) continue;
      final label = item['formatted_address']?.toString().trim() ?? query;
      results.add(RouteDestination(label.isEmpty ? query : label, point));
    }
    return results;
  }

  Future<List<RouteDestination>> _searchPhoton(
    String query, {
    LatLng? near,
    CancelToken? cancelToken,
  }) async {
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
    return results;
  }

  Future<RoadRoute> route(
    LatLng origin,
    LatLng destination, {
    CancelToken? cancelToken,
  }) async {
    String? googleError;
    if (_useGoogleDirections) {
      try {
        final response = await _client.get(
          'https://maps.googleapis.com/maps/api/directions/json',
          queryParameters: {
            'origin': '${origin.latitude},${origin.longitude}',
            'destination': '${destination.latitude},${destination.longitude}',
            'mode': 'driving',
            'departure_time': 'now',
            'alternatives': 'false',
            'key': _googleApiKey,
          },
          cancelToken: cancelToken,
        );
        if (response.data is Map) {
          final data = Map<String, dynamic>.from(response.data);
          final status = data['status']?.toString();
          if (status == 'OK' || status == 'ZERO_RESULTS' || status == 'NOT_FOUND') {
            return RoadRoute.fromGoogleDirections(data);
          }
          googleError = data['error_message']?.toString().trim();
          if (googleError == null || googleError.isEmpty) {
            googleError = 'Google Directions error: ${status ?? 'unknown'}';
          }
        }
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) rethrow;
        googleError = e.message ?? 'Google Directions request failed.';
      } catch (e) {
        if (e is StateError) rethrow;
        googleError = e.toString();
      }
    }

    try {
      final coordinates =
          '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}';
      final response = await _client.get(
        _endpoint(_routingUrl, '/route/v1/driving/$coordinates'),
        queryParameters: {
          'overview': 'full',
          'geometries': 'geojson',
          'steps': 'true',
          'alternatives': 'false',
        },
        cancelToken: cancelToken,
      );
      if (response.data is! Map) {
        throw const FormatException('Invalid route response.');
      }
      return RoadRoute.fromJson(Map<String, dynamic>.from(response.data));
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      if (googleError != null) {
        throw StateError(googleError);
      }
      rethrow;
    } catch (e) {
      if (googleError != null && e is! StateError) {
        throw StateError(googleError);
      }
      rethrow;
    }
  }

  void dispose() {
    if (_ownsClient) _client.close(force: true);
  }
}
