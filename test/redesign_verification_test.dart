import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mdrrmo_flutter/data/api_client.dart';
import 'package:mdrrmo_flutter/data/resident_models.dart';
import 'package:mdrrmo_flutter/screens/driver-responder/driver_form_screen.dart';
import 'package:mdrrmo_flutter/screens/driver-responder/emergency_form_screen.dart';
import 'package:mdrrmo_flutter/screens/driver-responder/shell.dart';
import 'package:mdrrmo_flutter/screens/location_access_gate.dart';
import 'package:mdrrmo_flutter/screens/pending_submissions_screen.dart';
import 'package:mdrrmo_flutter/screens/record_details_screen.dart';
import 'package:mdrrmo_flutter/screens/resident/resident_shell.dart';
import 'package:mdrrmo_flutter/screens/route_navigation_screen.dart';
import 'package:mdrrmo_flutter/services/driver_realtime.dart';
import 'package:mdrrmo_flutter/services/driver_tracking.dart';
import 'package:mdrrmo_flutter/services/pending_submissions.dart';
import 'package:mdrrmo_flutter/state/driver_responder_state.dart';
import 'package:mdrrmo_flutter/state/resident_state.dart';
import 'package:mdrrmo_flutter/ui/kit.dart';

import 'hospital_routes_test.dart' show HospitalApi, HospitalRouting;
import 'resident_ui_test.dart' show ResidentUiApi;
import 'responder_ui_test.dart' show ResponderUiApi;
import 'route_navigation_test.dart' show NavigationLocation;

class _RedesignAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    final Object body;
    if (path.endsWith('/auth/mobile/account')) {
      body = {
        'name': 'Ana Santos',
        'email': 'ana@example.test',
        'contact': '09171234567',
        'house_no': '12',
        'street': 'Rizal St',
        'barangay': 'San Juan',
        'city': 'Balagtas',
        'province': 'Bulacan',
        'resident': true,
        'has_avatar': false,
      };
    } else if (path.contains('voice-calls')) {
      body = {'calls': []};
    } else if (path.endsWith('/resident/reports/12') ||
        path.endsWith('/driver-responder/reports/12')) {
      body = {
        'id': 12,
        'reference': 'RPT-12',
        'type': 'Medical Emergency',
        'status': path.contains('driver-responder') ? 'dispatched' : 'pending',
        'priority': 'high',
        'location': 'Barangay San Juan, Balagtas',
        'description': 'Resident needs medical transport.',
        'reported_at': '2030-01-02T09:00:00Z',
        'can_edit': true,
      };
    } else {
      body = {};
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeLocationSource implements MapLocationSource {
  @override
  Future<bool> enabled() async => false;

  @override
  Future<PermissionStatus> permission() async => PermissionStatus.denied;

  @override
  Future<void> enable() async {}

  @override
  Future<void> settings(bool serviceDisabled) async {}

  @override
  Stream<GpsFix> get positions => const Stream.empty();
}

ResidentState _residentState() => ResidentState(
  const ResidentProfile(name: 'Ana Santos', contact: '', address: ''),
  api: ResidentUiApi(),
);

Widget _darkApp(Widget home, {double scale = 1.0}) {
  return MaterialApp(
    theme: AppTheme.materialLight,
    darkTheme: AppTheme.materialDark,
    themeMode: ThemeMode.dark,
    builder: (context, child) => FTheme(
      data: AppTheme.dark,
      child: FToaster(
        child: FTooltipGroup(
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    ),
    home: home,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpClientAdapter previousAdapter;

  setUp(() {
    dotenv.loadFromString(envString: 'API_URL=https://example.test/api');
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': 'test-token',
      'account_key': 'resident:1',
    });
    previousAdapter = dio.httpClientAdapter;
    dio.httpClientAdapter = _RedesignAdapter();

    final cache = Directory('.tmp/redesign-map-cache')
      ..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => cache.absolute.path,
        );
  });

  tearDown(() {
    dio.httpClientAdapter = previousAdapter;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  testWidgets(
    'ThemeMode.dark renders ResidentShell, Responder Shell, and forms cleanly',
    (tester) async {
      final resident = _residentState();
      await resident.load();
      await tester.pumpWidget(
        _darkApp(
          ResidentScope(state: resident, child: const ResidentShell()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Balagtas MDRRMO'), findsOneWidget);
      expect(find.byKey(const ValueKey('resident-sos-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      resident.dispose();

      final responder = ResponderState(
        api: ResponderUiApi(assignedServices: true),
      );
      await responder.load();
      final realtime = DriverRealtime(client: dio);
      final tracking = DriverTracking(client: dio);
      await tester.pumpWidget(
        _darkApp(
          ResponderScope(
            state: responder,
            child: Shell(
              tracking: tracking,
              realtime: realtime,
              onLocationAccessChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Dispatch'), findsOneWidget);
      await tester.tap(find.text('Team').last);
      await tester.pumpAndSettle();
      expect(find.text('Assigned ambulance'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      realtime.dispose();
      tracking.dispose();

      final formResponder = ResponderState(
        api: ResponderUiApi(assignedServices: true),
      );
      await formResponder.load();
      await tester.pumpWidget(
        _darkApp(
          ResponderScope(
            state: formResponder,
            child: const DriverFormScreen(initialReportId: 12),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Authorization'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        _darkApp(
          ResponderScope(
            state: formResponder,
            child: const EmergencyFormScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Emergency report'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        _darkApp(PendingSubmissionsScreen(onRecovered: () async {})),
      );
      await tester.pumpAndSettle();
      expect(find.text('No pending submissions'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        _darkApp(
          LocationAccessGate(
            source: _FakeLocationSource(),
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Device location services'), findsOneWidget);
      expect(find.text('MDRRMO location permission'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      responder.dispose();
      formResponder.dispose();
    },
  );

  testWidgets(
    'Resident omits Voice calls and Account & profile while Responder More options only shows Refresh information and Log out',
    (tester) async {
      final resident = _residentState();
      await resident.load();
      await tester.pumpWidget(
        _darkApp(
          ResidentScope(state: resident, child: const ResidentShell()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Voice calls'), findsNothing);
      await tester.tap(find.byIcon(AppIcons.more));
      await tester.pumpAndSettle();
      expect(find.text('Account & profile'), findsNothing);
      expect(find.text('Search records'), findsNothing);
      expect(find.text('Unconfirmed submissions'), findsNothing);
      expect(find.text('Refresh information'), findsOneWidget);
      expect(find.byIcon(AppIcons.refresh), findsNothing);
      expect(find.byIcon(AppIcons.logout), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      resident.dispose();

      final responder = ResponderState(api: ResponderUiApi());
      await responder.load();
      final realtime = DriverRealtime(client: dio);
      final tracking = DriverTracking(client: dio);
      await tester.pumpWidget(
        _darkApp(
          ResponderScope(
            state: responder,
            child: Shell(
              tracking: tracking,
              realtime: realtime,
              onLocationAccessChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(AppIcons.more));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.text('Account & profile'), findsNothing);
      expect(find.text('Reports I submitted'), findsNothing);
      expect(find.text('Unconfirmed submissions'), findsNothing);
      expect(find.text('Search records'), findsNothing);
      expect(find.text('Refresh information'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
      expect(find.byIcon(AppIcons.refresh), findsNothing);
      expect(find.byIcon(AppIcons.logout), findsNothing);
      await tester.tap(find.text('Refresh information'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      realtime.dispose();
      tracking.dispose();
      responder.dispose();
    },
  );

  testWidgets(
    'compact 320dp width with 2.0x textScaler renders updated shells without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final resident = _residentState();
      await resident.load();
      await tester.pumpWidget(
        _darkApp(
          ResidentScope(state: resident, child: const ResidentShell()),
          scale: 2.0,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      resident.dispose();

      final responder = ResponderState(
        api: ResponderUiApi(assignedServices: true),
      );
      await responder.load();
      final realtime = DriverRealtime(client: dio);
      final tracking = DriverTracking(client: dio);
      await tester.pumpWidget(
        _darkApp(
          ResponderScope(
            state: responder,
            child: Shell(
              tracking: tracking,
              realtime: realtime,
              onLocationAccessChanged: (_) {},
            ),
          ),
          scale: 2.0,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Team').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        _darkApp(PendingSubmissionsScreen(onRecovered: () async {}), scale: 2.0),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      realtime.dispose();
      tracking.dispose();
      responder.dispose();
    },
  );

  testWidgets(
    'RouteNavigationScreen compact (<480dp) exposes DraggableScrollableSheet controls and hospitals',
    (tester) async {
      tester.view.physicalSize = const Size(390, 440);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final hospitalApi = HospitalApi();
      final routing = HospitalRouting();
      await tester.pumpWidget(
        _darkApp(
          RouteNavigationScreen(
            address: 'Incident location',
            destination: const LatLng(14.825, 120.91),
            reportId: 22,
            hospitalApi: hospitalApi,
            routing: routing,
            location: NavigationLocation(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(find.byTooltip('Update route'), findsOneWidget);
      expect(find.byTooltip('Show route'), findsOneWidget);
      final sheetScroll = find.descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Recommended hospitals'),
        60,
        scrollable: sheetScroll,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recommended hospitals'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Bulacan Medical Center'),
        60,
        scrollable: sheetScroll,
      );
      expect(find.text('Bulacan Medical Center'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      hospitalApi.dispose();
      routing.dispose();
    },
  );

  testWidgets(
    'AppScaffold footer removes top MediaQuery padding so NavigationBar has no gap above icons',
    (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 48, bottom: 24),
          ),
          child: MaterialApp(
            theme: AppTheme.materialLight,
            home: FTheme(
              data: AppTheme.light,
              child: AppScaffold(
                footer: NavigationBar(
                  selectedIndex: 0,
                  onDestinationSelected: (_) {},
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(AppIcons.home),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(AppIcons.form),
                      label: 'Reports',
                    ),
                  ],
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final navBarRect = tester.getRect(find.byType(NavigationBar));
      final iconRect = tester.getRect(find.byIcon(AppIcons.home));

      // NavigationBar height should only include theme height (64) + bottom padding (24),
      // without the 48px top status-bar inset above the icons.
      expect(navBarRect.height, 88);
      expect(iconRect.top - navBarRect.top, lessThan(20));
    },
  );

  testWidgets(
    'small 320dp phone surfaces Resident Current status and Role pending-sync / connection banners cleanly',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final queuedResident = await tester.runAsync(
        () => PendingSubmissions.prepare(
          '/resident/reports',
          {'location': 'Barangay San Juan'},
        ),
      );
      try {
        final resident = _residentState();
        await resident.load();
        await tester.pumpWidget(
          _darkApp(
            ResidentScope(
              state: resident,
              child: const ResidentShell(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Current status'), findsOneWidget);
        expect(find.text('Waiting for review'), findsWidgets);
        expect(find.text('1 unsynced request'), findsOneWidget);
        expect(find.text('Review & send'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        resident.dispose();
      } finally {
        if (queuedResident != null) {
          await tester.runAsync(
            () => PendingSubmissions.complete(queuedResident.key),
          );
        }
      }

      final queuedDriver = await tester.runAsync(
        () => PendingSubmissions.prepare(
          '/driver-responder/reports',
          {'location': 'MacArthur Highway'},
        ),
      );
      final responder = ResponderState(
        api: ResponderUiApi(assigned: true, assignedServices: true),
      );
      await responder.load();
      final realtime = DriverRealtime(client: dio);
      final tracking = DriverTracking(client: dio);
      try {
        await tester.pumpWidget(
          _darkApp(
            ResponderScope(
              state: responder,
              child: Shell(
                tracking: tracking,
                realtime: realtime,
                onLocationAccessChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();

        expect(find.text('1 unsynced report'), findsOneWidget);
        expect(find.widgetWithText(AppButton, 'Start trip'), findsOneWidget);
        expect(find.textContaining('Live'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        realtime.dispose();
        tracking.dispose();
        responder.dispose();
        if (queuedDriver != null) {
          await tester.runAsync(
            () => PendingSubmissions.complete(queuedDriver.key),
          );
        }
      }
    },
  );

  testWidgets(
    'Resident RecordDetailsScreen renders low-icon grouped details on 320dp screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_darkApp(const RecordDetailsScreen(id: 12)));
      await tester.pumpAndSettle();

      expect(find.text('Medical Emergency'), findsOneWidget);
      expect(find.text('Waiting for review'), findsOneWidget);
      expect(
        find.text(
          'MDRRMO has received your report and is reviewing it now.',
        ),
        findsOneWidget,
      );
      expect(find.text('Incident details'), findsOneWidget);
      expect(find.text('Response team'), findsOneWidget);
      expect(find.text('Activity timeline'), findsOneWidget);
      expect(find.text('Voice call invitations'), findsNothing);
      expect(find.byType(AppSectionGroup), findsAtLeastNWidgets(2));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        _darkApp(
          const RecordDetailsScreen(
            key: ValueKey('driver-details'),
            id: 12,
            driver: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Medical Emergency'), findsOneWidget);
      expect(
        find.text('Assigned for emergency response.'),
        findsOneWidget,
      );
      expect(find.text('Incident details'), findsOneWidget);
      expect(find.text('Activity timeline'), findsOneWidget);
      expect(find.byType(AppSectionGroup), findsAtLeastNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
