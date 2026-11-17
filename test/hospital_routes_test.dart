import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mdrrmo_flutter/data/api/driver_service.api.dart';
import 'package:mdrrmo_flutter/data/hospital.dart';
import 'package:mdrrmo_flutter/screens/route_navigation_screen.dart';
import 'package:mdrrmo_flutter/services/road_routing.dart';

import 'responder_ui_test.dart' show app;
import 'route_navigation_test.dart' show NavigationLocation, routeJson;

class HospitalApi extends DriverApi {
  HospitalApi() : super(Dio());
  final requestedReports = <int>[];

  @override
  Future<List<HospitalRecommendation>> fetchHospitals(int reportId) async {
    requestedReports.add(reportId);
    return const [
      HospitalRecommendation(
        id: 1,
        name: 'Bulacan Medical Center',
        address: 'Malolos, Bulacan',
        point: LatLng(14.858880, 120.817018),
        distanceKm: 10.5,
        specialtyMatch: true,
      ),
    ];
  }
}

class HospitalRouting extends RoadRouting {
  final destinations = <LatLng>[];

  @override
  Future<RoadRoute> route(
    LatLng origin,
    LatLng destination, {
    CancelToken? cancelToken,
  }) async {
    destinations.add(destination);
    return RoadRoute.fromJson(routeJson());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'hospital data preserves unknown bed availability and rejects invalid pins',
    () {
      final data = <String, dynamic>{
        'id': 1,
        'name': 'Hospital',
        'address': 'Bulacan',
        'lat': 14.82,
        'lng': 120.91,
        'distance': 2.5,
        'availableBeds': null,
        'contactNumber': null,
        'match': true,
      };
      final hospital = HospitalRecommendation.fromJson(data);
      expect(hospital.availableBeds, isNull);
      expect(hospital.specialtyMatch, isTrue);
      expect(hospital.point, const LatLng(14.82, 120.91));
      expect(
        () => HospitalRecommendation.fromJson({...data, 'lat': 100}),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'assignment Routes shows hospital pins and can switch between hospital and incident',
    (tester) async {
      final cache = Directory('.tmp/hospital-map-cache')
        ..createSync(recursive: true);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => cache.absolute.path,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        ),
      );
      final api = HospitalApi();
      final routing = HospitalRouting();
      const incident = LatLng(14.825, 120.91);
      await tester.pumpWidget(
        app(
          RouteNavigationScreen(
            address: 'Incident location',
            destination: incident,
            reportId: 22,
            hospitalApi: api,
            routing: routing,
            location: NavigationLocation(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.requestedReports, [22]);
      final mapWidget = tester.widget<gmaps.GoogleMap>(
        find.byType(gmaps.GoogleMap),
      );
      expect(
        mapWidget.markers.any(
          (m) => m.infoWindow.title == 'Bulacan Medical Center',
        ),
        isTrue,
      );
      expect(routing.destinations.last, incident);
      await tester.tap(find.text('Recommended hospitals'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Bed availability unconfirmed'),
        findsOneWidget,
      );
      await tester.tap(find.text('Bulacan Medical Center'));
      await tester.pumpAndSettle();
      expect(routing.destinations.last, const LatLng(14.858880, 120.817018));
      await tester.ensureVisible(find.text('Return to incident route'));
      await tester.tap(find.text('Return to incident route'));
      await tester.pumpAndSettle();
      expect(routing.destinations.last, incident);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
      routing.dispose();
    },
  );
}
