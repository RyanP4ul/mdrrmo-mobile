import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mdrrmo_flutter/data/api/driver_service.api.dart';
import 'package:mdrrmo_flutter/data/hospital.dart';
import 'package:mdrrmo_flutter/data/paged_records.dart';
import 'package:mdrrmo_flutter/services/driver_tracking.dart';
import 'package:mdrrmo_flutter/services/incident_location.dart';
import 'package:mdrrmo_flutter/services/road_routing.dart';
import 'package:mdrrmo_flutter/services/route_navigation.dart';
import 'package:mdrrmo_flutter/screens/route_navigation_screen.dart';
import 'package:mdrrmo_flutter/state/driver_responder_state.dart';

import 'responder_ui_test.dart' show app;

Map<String, dynamic> routeJson() => {
  'code': 'Ok',
  'routes': [
    {
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [120.90, 14.82],
          [120.901, 14.824],
          [120.91, 14.825],
        ],
      },
      'distance': 1600,
      'duration': 300,
      'legs': [
        {
          'steps': [
            {
              'name': 'Main Street',
              'distance': 400,
              'maneuver': {'type': 'turn', 'modifier': 'right'},
            },
          ],
        },
      ],
    },
  ],
};

class RoutingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool noRoute = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(
        options.path.contains('/api/')
            ? {
                'features': [
                  {
                    'geometry': {
                      'type': 'Point',
                      'coordinates': [120.91, 14.825],
                    },
                    'properties': {'name': 'Town hall', 'city': 'Balagtas'},
                  },
                ],
              }
            : noRoute
            ? {'code': 'NoRoute', 'routes': []}
            : routeJson(),
      ),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class NavigationLocation implements IncidentLocationSource {
  LatLng point = const LatLng(14.82, 120.90);
  @override
  Future<LatLng> current() async => point;
}

class NavigationRouting extends RoadRouting {
  bool fail = false;
  int routes = 0;
  @override
  Future<RoadRoute> route(
    LatLng origin,
    LatLng destination, {
    CancelToken? cancelToken,
  }) async {
    routes++;
    if (fail) throw StateError('No driving route was found.');
    return RoadRoute.fromJson(routeJson());
  }

  @override
  Future<List<RouteDestination>> search(
    String address, {
    LatLng? near,
    CancelToken? cancelToken,
  }) async => [
    const RouteDestination('Town hall, Balagtas', LatLng(14.825, 120.91)),
  ];
}

void main() {
  setUp(() {
    final cache = Directory('.tmp/navigation-map-cache')
      ..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => cache.absolute.path,
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        ),
  );

  test('road routing preserves full road geometry and sends longitude before latitude', () async {
    final adapter = RoutingAdapter();
    final client = Dio()..httpClientAdapter = adapter;
    final routing = RoadRouting(
      client: client,
      routingUrl: 'https://routing.test',
      geocodingUrl: 'https://places.test',
    );
    final result = await routing.route(
      const LatLng(14.82, 120.90),
      const LatLng(14.825, 120.91),
    );
    expect(result.points, [
      const LatLng(14.82, 120.90),
      const LatLng(14.824, 120.901),
      const LatLng(14.825, 120.91),
    ]);
    expect(result.distance, 1600);
    expect(result.directions.single, contains('Main Street'));
    expect(
      adapter.requests.single.path,
      contains('/route/v1/driving/120.9,14.82;120.91,14.825'),
    );
    expect(adapter.requests.single.queryParameters['geometries'], 'geojson');
    expect(adapter.requests.single.queryParameters['overview'], 'full');
    expect(
      adapter.requests.single.headers.containsKey('Authorization'),
      isFalse,
    );
    adapter.noRoute = true;
    await expectLater(
      routing.route(const LatLng(14.82, 120.90), const LatLng(14.825, 120.91)),
      throwsStateError,
    );
    final invalid = routeJson();
    (invalid['routes'] as List).first['geometry']['coordinates'] = [
      [120.9, 1000],
      [120.91, 14.825],
    ];
    expect(() => RoadRoute.fromJson(invalid), throwsFormatException);
    client.close();
  });

  test(
    'address lookup returns candidates and caches repeated searches',
    () async {
      final adapter = RoutingAdapter();
      final client = Dio()..httpClientAdapter = adapter;
      final routing = RoadRouting(
        client: client,
        geocodingUrl: 'https://places.test/',
      );
      final results = await routing.search(
        'Town hall',
        near: const LatLng(14.82, 120.90),
      );
      await routing.search('Town hall');
      expect(results.single.point, const LatLng(14.825, 120.91));
      expect(results.single.label, 'Town hall, Balagtas');
      expect(adapter.requests.length, 1);
      expect(adapter.requests.single.queryParameters['countrycode'], 'PH');
      client.close();
    },
  );

  testWidgets(
    'active assignment opens an in-app GoogleMap route with road geometry and GPS refresh',
    (tester) async {
      final routing = NavigationRouting();
      final location = NavigationLocation();
      await tester.pumpWidget(
        app(
          RouteNavigationScreen(
            address: 'Incident location',
            destination: const LatLng(14.825, 120.91),
            routing: routing,
            location: location,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(gmaps.GoogleMap), findsOneWidget);
      expect(
        tester
            .widget<gmaps.GoogleMap>(find.byType(gmaps.GoogleMap))
            .polylines
            .firstWhere((p) => p.polylineId.value == 'route_main')
            .points
            .length,
        3,
      );
      expect(find.text('5 min'), findsOneWidget);
      expect(find.text('1.6 km'), findsOneWidget);
      expect(find.textContaining('Turn right onto Main Street'), findsOneWidget);
      location.point = const LatLng(14.821, 120.901);
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(routing.routes, 2);
      routing.fail = true;
      await tester.tap(find.byTooltip('Update route'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<gmaps.GoogleMap>(find.byType(gmaps.GoogleMap)).polylines,
        isEmpty,
      );
      expect(find.text('No driving route was found.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      routing.dispose();
    },
  );

  testWidgets(
    'scheduled service confirms an address destination before drawing its road route',
    (tester) async {
      final routing = NavigationRouting();
      await tester.pumpWidget(
        app(
          RouteNavigationScreen(
            address: 'Town hall',
            routing: routing,
            location: NavigationLocation(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<gmaps.GoogleMap>(find.byType(gmaps.GoogleMap)).polylines,
        isEmpty,
      );
      await tester.tap(find.byTooltip('Find destination'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Town hall, Balagtas'));
      await tester.pumpAndSettle();
      expect(routing.routes, 0);
      await tester.tap(find.text('Confirm destination and route'));
      await tester.pumpAndSettle();
      expect(routing.routes, 1);
      expect(
        tester.widget<gmaps.GoogleMap>(find.byType(gmaps.GoogleMap)).polylines,
        isNotEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      routing.dispose();
    },
  );

  testWidgets(
    'navigation helper pushes the embedded map instead of launching an external application',
    (tester) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => navigateToDestination(
                context,
                address: 'Town hall',
                latitude: 14.825,
                longitude: 120.91,
              ),
              child: const Text('Navigate'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Navigate'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.byType(RouteNavigationScreen), findsOneWidget);
      expect(
        tester
            .widget<RouteNavigationScreen>(find.byType(RouteNavigationScreen))
            .destination,
        const LatLng(14.825, 120.91),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'tapping map toggles map-only mode without resetting route or markers',
    (tester) async {
      final routing = NavigationRouting();
      final location = NavigationLocation();
      await tester.pumpWidget(
        app(
          RouteNavigationScreen(
            address: 'Incident location',
            destination: const LatLng(14.825, 120.91),
            routing: routing,
            location: location,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('5 min'), findsOneWidget);
      expect(find.byTooltip('Show route'), findsOneWidget);
      expect(
        tester.widget<gmaps.GoogleMap>(find.byType(gmaps.GoogleMap)).polylines,
        isNotEmpty,
      );
      expect(
        tester.widget<gmaps.GoogleMap>(find.byType(gmaps.GoogleMap)).markers,
        isNotEmpty,
      );

      tester
          .widget<gmaps.GoogleMap>(find.byType(gmaps.GoogleMap))
          .onTap
          ?.call(const gmaps.LatLng(14.82, 120.90));
      await tester.pumpAndSettle();

      expect(find.text('5 min'), findsNothing);
      expect(find.byTooltip('Show route'), findsNothing);
      expect(
        tester.widget<gmaps.GoogleMap>(find.byType(gmaps.GoogleMap)).polylines,
        isNotEmpty,
      );
      expect(
        tester.widget<gmaps.GoogleMap>(find.byType(gmaps.GoogleMap)).markers,
        isNotEmpty,
      );

      tester
          .widget<gmaps.GoogleMap>(find.byType(gmaps.GoogleMap))
          .onTap
          ?.call(const gmaps.LatLng(14.82, 120.90));
      await tester.pumpAndSettle();

      expect(find.text('5 min'), findsOneWidget);
      expect(find.byTooltip('Show route'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      routing.dispose();
    },
  );

  testWidgets(
    'automatic On Scene triggers only on reliable GPS within radius and cannot duplicate',
    (tester) async {
      final now = DateTime(2026, 11, 14, 11, 0, 0);
      const incident = LatLng(14.825, 120.91);
      final location = DetailedNavigationLocation(
        GpsFix(
          latitude: incident.latitude,
          longitude: incident.longitude,
          accuracy: 250, // Too inaccurate for automatic arrival
          time: now,
        ),
      );
      final api = FakeNavDriverApi(initialVehicleStatus: 'en-route');
      final state = ResponderState(api: api);
      await state.load();
      final routing = NavigationRouting();

      await tester.pumpWidget(
        app(
          RouteNavigationScreen(
            address: 'Incident location',
            destination: incident,
            reportId: 10,
            responderState: state,
            hospitalApi: api,
            routing: routing,
            location: location,
            arrivalRadiusMeters: 100,
            now: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Poor accuracy must NOT auto-mark On Scene; En Route has no manual button,
      // and hospital suggestions are hidden until Transporting.
      expect(api.statusUpdates, isEmpty);
      expect(find.text('Mark as On Scene'), findsNothing);
      expect(find.text('Recommended hospitals'), findsNothing);
      expect(
        tester
            .widget<gmaps.GoogleMap>(find.byType(gmaps.GoogleMap))
            .markers
            .any((m) => m.infoWindow.title == 'Bulacan Medical Center'),
        isFalse,
      );
      expect(
        find.text('En route — On Scene triggers automatically within 5 m of the incident.'),
        findsOneWidget,
      );

      // Now provide a reliable, recent GPS fix within 100m (override radius).
      location.fix = GpsFix(
        latitude: incident.latitude,
        longitude: incident.longitude,
        accuracy: 12,
        time: now,
      );
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();

      expect(api.statusUpdates, ['on-scene']);
      expect(find.text('Transporting'), findsOneWidget);

      // Next GPS tick must NOT mark arrival a second time.
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(api.statusUpdates, ['on-scene']);

      await tester.pumpWidget(const SizedBox());
      routing.dispose();
      state.dispose();
    },
  );

  testWidgets(
    'en-route has no manual On Scene button and Transporting routes to nearest available hospital',
    (tester) async {
      final now = DateTime(2026, 11, 14, 11, 0, 0);
      const incident = LatLng(14.825, 120.91);
      final location = DetailedNavigationLocation(
        GpsFix(
          latitude: 14.820,
          longitude: 120.900,
          accuracy: 150,
          time: now,
        ),
      );
      final api = FakeNavDriverApi(
        initialVehicleStatus: 'available',
        initialResponseStatus: 'on-scene',
      );
      final state = ResponderState(api: api);
      await state.load();
      final routing = NavigationRouting();

      await tester.pumpWidget(
        app(
          RouteNavigationScreen(
            address: 'Incident location',
            destination: incident,
            reportId: 10,
            responderState: state,
            hospitalApi: api,
            routing: routing,
            location: location,
            arrivalRadiusMeters: 5,
            now: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Transporting'), findsOneWidget);
      expect(find.text('Recommended hospitals'), findsNothing);
      await tester.tap(find.text('Transporting'));
      await tester.pumpAndSettle();

      expect(api.statusUpdates, ['transporting']);
      expect(find.text('Complete dispatch'), findsOneWidget);
      expect(find.text('Not Available'), findsOneWidget);
      expect(find.text('Hospital'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      routing.dispose();
      state.dispose();
    },
  );

  testWidgets(
    'hospital arrival prompts for manual completion, respects map-only mode, and Not Yet does not repeat',
    (tester) async {
      final now = DateTime(2026, 11, 14, 11, 0, 0);
      const incident = LatLng(14.825, 120.91);
      const hospitalPoint = LatLng(14.858880, 120.817018);
      final location = DetailedNavigationLocation(
        GpsFix(
          latitude: incident.latitude,
          longitude: incident.longitude,
          accuracy: 10,
          time: now,
        ),
      );
      final api = FakeNavDriverApi(
        initialVehicleStatus: 'available',
        initialResponseStatus: 'transporting',
      );
      final state = ResponderState(api: api);
      await state.load();
      final routing = NavigationRouting();

      await tester.pumpWidget(
        app(
          RouteNavigationScreen(
            address: 'Incident location',
            destination: incident,
            reportId: 10,
            responderState: state,
            hospitalApi: api,
            routing: routing,
            location: location,
            arrivalRadiusMeters: 100,
            now: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select hospital leg.
      // Bulacan Medical Center is auto-selected in transporting mode.
      expect(
        find.textContaining('Bulacan Medical Center'),
        findsWidgets,
      );

      // Enter map-only mode, then arrive at hospital.
      tester
          .widget<gmaps.GoogleMap>(find.byType(gmaps.GoogleMap))
          .onTap
          ?.call(const gmaps.LatLng(14.82, 120.90));
      await tester.pumpAndSettle();
      location.fix = GpsFix(
        latitude: hospitalPoint.latitude,
        longitude: hospitalPoint.longitude,
        accuracy: 10,
        time: now,
      );
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();

      // Must NOT complete automatically and must stay hidden in map-only mode.
      expect(api.statusUpdates, isEmpty);
      expect(find.text('Not Yet'), findsNothing);

      // Restore controls: prompt is visible with Arrived & Not Yet.
      tester
          .widget<gmaps.GoogleMap>(find.byType(gmaps.GoogleMap))
          .onTap
          ?.call(const gmaps.LatLng(14.82, 120.90));
      await tester.pumpAndSettle();
      expect(find.text('Arrived at Bulacan Medical Center'), findsOneWidget);
      expect(find.text('Not Yet'), findsOneWidget);
      expect(find.text('Arrived'), findsOneWidget);
      expect(find.text('Complete dispatch'), findsOneWidget);

      // Tap Not Yet: keeps dispatch active and does not repeat on next GPS tick.
      await tester.tap(find.text('Not Yet'));
      await tester.pumpAndSettle();
      expect(api.statusUpdates, isEmpty);
      expect(find.text('Arrived at Bulacan Medical Center'), findsNothing);

      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(find.text('Arrived at Bulacan Medical Center'), findsNothing);
      expect(find.text('Complete dispatch'), findsOneWidget);

      // Complete dispatch manually via the bottom action button + confirmation.
      await tester.tap(find.text('Complete dispatch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arrived').last);
      await tester.pumpAndSettle();
      expect(api.statusUpdates, ['arrived']);

      await tester.pumpWidget(const SizedBox());
      routing.dispose();
      state.dispose();
    },
  );

  test('Google Directions parser decodes polyline, traffic ETA, and turn steps', () {
    final route = RoadRoute.fromGoogleDirections({
      'status': 'OK',
      'routes': [
        {
          'overview_polyline': {'points': '_p~iF~ps|U_ulLnnqC_mqNvxq`@'},
          'legs': [
            {
              'distance': {'value': 2400},
              'duration': {'value': 420},
              'duration_in_traffic': {'value': 480},
              'steps': [
                {
                  'html_instructions': 'Turn <b>right</b> onto Main St',
                  'maneuver': 'turn-right',
                  'distance': {'value': 450},
                  'duration': {'value': 60},
                  'start_location': {'lat': 14.82, 'lng': 120.90},
                  'end_location': {'lat': 14.824, 'lng': 120.901},
                },
                {
                  'html_instructions': 'Turn <b>left</b> onto Rizal Ave',
                  'maneuver': 'turn-left',
                  'distance': {'value': 1950},
                  'duration': {'value': 420},
                  'start_location': {'lat': 14.824, 'lng': 120.901},
                  'end_location': {'lat': 14.825, 'lng': 120.91},
                },
              ],
            },
          ],
        },
      ],
    });

    expect(route.points.length, 3);
    expect(route.distance, 2400);
    expect(route.duration, 480);
    expect(route.steps.length, 2);
    expect(route.steps.first.instruction, 'Turn right onto Main St');
    expect(route.steps.first.modifier, 'right');
    expect(route.steps.last.instruction, 'Turn left onto Rizal Ave');
  });

  testWidgets(
    'Waze-style turn banner shows Then preview, speedometer, and Re-center on pan',
    (tester) async {
      final now = DateTime(2026, 11, 14, 11, 0, 0);
      final routing = _MultiStepRouting();
      final location = DetailedNavigationLocation(
        GpsFix(
          latitude: 14.82,
          longitude: 120.90,
          accuracy: 8,
          time: now,
          speed: 12.5, // 45 km/h
          heading: 90,
        ),
      );
      await tester.pumpWidget(
        app(
          RouteNavigationScreen(
            address: 'Incident location',
            destination: const LatLng(14.825, 120.91),
            routing: routing,
            location: location,
            now: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Turn right onto Main St'), findsOneWidget);
      expect(find.text('Then'), findsOneWidget);
      expect(find.text('Turn left onto Rizal Ave'), findsOneWidget);
      expect(find.text('45'), findsOneWidget);
      expect(find.text('km/h'), findsOneWidget);

      // Simulate user panning away from follow mode.
      expect(find.text('Re-center'), findsNothing);
      tester
          .widget<gmaps.GoogleMap>(find.byType(gmaps.GoogleMap))
          .onCameraMoveStarted
          ?.call();
      await tester.pumpAndSettle();
      expect(find.text('Re-center'), findsOneWidget);

      await tester.tap(find.text('Re-center'));
      await tester.pumpAndSettle();
      expect(find.text('Re-center'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      routing.dispose();
    },
  );
}

class _MultiStepRouting extends RoadRouting {
  @override
  Future<RoadRoute> route(
    LatLng origin,
    LatLng destination, {
    CancelToken? cancelToken,
  }) async {
    return RoadRoute.fromGoogleDirections({
      'status': 'OK',
      'routes': [
        {
          'overview_polyline': {'points': '_p~iF~ps|U_ulLnnqC_mqNvxq`@'},
          'legs': [
            {
              'distance': {'value': 2400},
              'duration': {'value': 480},
              'steps': [
                {
                  'html_instructions': 'Turn <b>right</b> onto Main St',
                  'maneuver': 'turn-right',
                  'distance': {'value': 450},
                  'duration': {'value': 60},
                  'start_location': {'lat': 14.82, 'lng': 120.90},
                  'end_location': {'lat': 14.824, 'lng': 120.901},
                },
                {
                  'html_instructions': 'Turn <b>left</b> onto Rizal Ave',
                  'maneuver': 'turn-left',
                  'distance': {'value': 1950},
                  'duration': {'value': 420},
                  'start_location': {'lat': 14.824, 'lng': 120.901},
                  'end_location': {'lat': 14.825, 'lng': 120.91},
                },
              ],
            },
          ],
        },
      ],
    });
  }
}

class DetailedNavigationLocation implements DetailedLocationSource {
  DetailedNavigationLocation(this.fix);
  GpsFix fix;

  @override
  Future<LatLng> current() async => LatLng(fix.latitude, fix.longitude);

  @override
  Future<GpsFix> currentFix() async => fix;
}

class FakeNavDriverApi extends DriverApi {
  FakeNavDriverApi({
    required this.initialVehicleStatus,
    this.initialResponseStatus,
  }) : super(Dio());
  String initialVehicleStatus;
  final String? initialResponseStatus;
  final statusUpdates = <String>[];

  @override
  Future<Map<String, dynamic>> fetchBootstrap() async => {
    'profile': {
      'name': 'Taylor Driver',
      'vehicle_type': 'ambulance',
      'vehicle_status': initialVehicleStatus,
      'vehicle_id': 5,
    },
    'teams': [],
    'incident_types': [],
    'assignments': [
      {
        'id': 10,
        'location': 'Incident location',
        'priority': 'high',
        'vehicle_status': initialVehicleStatus,
        'response_status': initialResponseStatus ?? initialVehicleStatus,
        'status': 'dispatched',
        'vehicle_id': 5,
      },
    ],
    'assignment': {
      'id': 10,
      'location': 'Incident location',
      'priority': 'high',
      'vehicle_status': initialVehicleStatus,
      'response_status': initialResponseStatus ?? initialVehicleStatus,
      'status': 'dispatched',
      'vehicle_id': 5,
    },
    'vehicles': [
      {
        'id': 5,
        'vehicle_type': 'ambulance',
        'vehicle_number': 'AMB-1',
        'vehicle_status': initialVehicleStatus,
      },
    ],
  };

  @override
  Future<RecordPage> fetchHistoryPage({int? before}) async =>
      const RecordPage([], null);

  @override
  Future<List<HospitalRecommendation>> fetchHospitals(int reportId) async =>
      const [
        HospitalRecommendation(
          id: 1,
          name: 'Bulacan Medical Center',
          address: 'Malolos, Bulacan',
          point: LatLng(14.858880, 120.817018),
          distanceKm: 10.5,
          specialtyMatch: true,
        ),
      ];

  @override
  Future<Map<String, dynamic>?> updateAssignmentStatus(
    int reportId,
    String status,
  ) => updateAssignmentStage(reportId, status);

  @override
  Future<Map<String, dynamic>?> updateAssignmentStage(
    int reportId,
    String status, {
    int? hospitalId,
    String? destination,
  }) async {
    statusUpdates.add(status);
    if (status == 'available' || status == 'arrived') return null;
    return {
      'id': reportId,
      'location': 'Incident location',
      'priority': 'high',
      'vehicle_status': status,
      'response_status': status,
      'hospital_id': hospitalId,
      'status': 'dispatched',
      'vehicle_id': 5,
    };
  }
}
