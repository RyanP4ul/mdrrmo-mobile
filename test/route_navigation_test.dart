import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mdrrmo_flutter/services/incident_location.dart';
import 'package:mdrrmo_flutter/services/road_routing.dart';
import 'package:mdrrmo_flutter/services/route_navigation.dart';
import 'package:mdrrmo_flutter/screens/route_navigation_screen.dart';

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
    'active assignment opens an in-app flutter_map route with road geometry and GPS refresh',
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
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(
        tester
            .widget<PolylineLayer>(find.byType(PolylineLayer))
            .polylines
            .single
            .points
            .length,
        3,
      );
      expect(find.text('1.6 km - 5 min estimated'), findsOneWidget);
      location.point = const LatLng(14.821, 120.901);
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(routing.routes, 2);
      routing.fail = true;
      await tester.tap(find.text('Update route'));
      await tester.pumpAndSettle();
      expect(find.byType(PolylineLayer), findsNothing);
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
      expect(find.byType(PolylineLayer), findsNothing);
      await tester.tap(find.byTooltip('Find destination'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Town hall, Balagtas'));
      await tester.pumpAndSettle();
      expect(routing.routes, 0);
      await tester.tap(find.text('Confirm destination and route'));
      await tester.pumpAndSettle();
      expect(routing.routes, 1);
      expect(find.byType(PolylineLayer), findsOneWidget);
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
}
