import 'dart:io';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mdrrmo_flutter/data/api/resident_service.api.dart';
import 'package:mdrrmo_flutter/data/resident_models.dart';
import 'package:mdrrmo_flutter/screens/resident/resident_shell.dart';
import 'package:mdrrmo_flutter/screens/resident/schedule_screen.dart';
import 'package:mdrrmo_flutter/screens/resident/report_screen.dart';
import 'package:mdrrmo_flutter/screens/resident/home_screen.dart';
import 'package:mdrrmo_flutter/screens/resident/resident_widgets.dart';
import 'package:mdrrmo_flutter/state/resident_state.dart';
import 'package:mdrrmo_flutter/services/incident_location.dart';
import 'package:mdrrmo_flutter/ui/kit.dart';

class FakeIncidentLocation implements IncidentLocationSource {
  FakeIncidentLocation(this.read);
  final Future<LatLng> Function() read;
  @override
  Future<LatLng> current() => read();
}

class ResidentUiApi extends ResidentApi {
  ResidentUiApi({this.accepted = true}) : super(Dio());
  final bool accepted;
  int markedRead = 0;
  int? cancelled;
  Map<String, dynamic> schedule(String status) => {
    'id': 8,
    'service_type': 'Medical Mission',
    'address': 'Town hall',
    'preferred_date': '2030-02-05',
    'preferred_time': '14:30',
    'status': status,
  };
  @override
  Future<Map<String, dynamic>> fetchBootstrap() async => {
    'profile': {
      'name': 'Ana Santos',
      'contact': '09123456789',
      'address': 'Barangay San Juan',
      'registration_status': accepted ? 'accepted' : 'pending',
    },
    'incident_types': [
      {'id': 1, 'name': 'Medical Emergency'},
      {'id': 2, 'name': 'Fire'},
    ],
    'reports': [
      for (final id in [10, 11])
        {
          'id': id,
          'reference': 'RPT-$id',
          'type': 'Medical Emergency',
          'location': 'Barangay San Juan, Balagtas',
          'reported_at': '2026-11-04T08:00:00Z',
          'status': id == 10 ? 'pending' : 'resolved',
        },
    ],
    'schedules': [schedule(cancelled == null ? 'pending' : 'cancelled')],
    'notifications': [
      for (final id in [1, 2])
        {
          'id': id,
          'message': 'Report update $id',
          'type': 'report_update',
          'created_at': '2026-11-04T08:00:00Z',
          'read_at': id == 1 ? null : '2026-11-04T08:01:00Z',
        },
    ],
    'unread_count': 1,
  };
  @override
  Future<void> markAllRead() async {
    markedRead++;
  }

  @override
  Future<Map<String, dynamic>> cancelSchedule(int id) async {
    cancelled = id;
    return {'schedule': schedule('cancelled')};
  }
}

Widget residentApp(
  ResidentState state, {
  Widget? child,
  double scale = 1,
  bool dark = false,
}) {
  final theme = dark ? FTheme.neutral.dark.touch : FTheme.neutral.light.touch;
  return MaterialApp(
    theme: theme.toApproximateMaterialTheme(),
    builder: (context, child) => FTheme(
      data: theme,
      child: FToaster(
        child: FTooltipGroup(
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    ),
    home: ResidentScope(
      state: state,
      child: child == null ? const ResidentShell() : Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    dotenv.loadFromString(envString: 'API_URL=https://example.test/api');
    FlutterSecureStorage.setMockInitialValues({});
    final cache = Directory('.tmp/resident-map-cache')
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
  ResidentState state(ResidentUiApi api) => ResidentState(
    const ResidentProfile(name: 'Ana Santos', contact: '', address: ''),
    api: api,
  );

  Future<ResidentState> openLocationForm(
    WidgetTester tester,
    IncidentLocationSource source,
  ) async {
    final resident = state(ResidentUiApi());
    await tester.pumpWidget(
      residentApp(
        resident,
        child: ResidentReportScreen(onDone: () {}, locationSource: source),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Medical Emergency'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Use my current location'));
    return resident;
  }

  testWidgets(
    'current location updates the incident pin and displayed coordinates',
    (tester) async {
      final resident = await openLocationForm(
        tester,
        FakeIncidentLocation(() async => const LatLng(14.830123, 120.912345)),
      );
      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Latitude:'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('14.830123'), findsOneWidget);
      expect(find.textContaining('120.912345'), findsOneWidget);
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(
        map.mapController!.camera.center.latitude,
        closeTo(14.830123, 0.000001),
      );
      expect(
        map.mapController!.camera.center.longitude,
        closeTo(120.912345, 0.000001),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      resident.dispose();
    },
  );

  testWidgets(
    'location failures show a retryable message without selecting a false pin',
    (tester) async {
      final resident = await openLocationForm(
        tester,
        FakeIncidentLocation(
          () async => throw const IncidentLocationException(
            'Allow location access or place the pin manually.',
          ),
        ),
      );
      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();
      expect(
        find.text('Allow location access or place the pin manually.'),
        findsOneWidget,
      );
      expect(find.textContaining('Latitude:'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Use my current location'),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      resident.dispose();
    },
  );

  testWidgets('changing incident type ignores a late GPS result', (
    tester,
  ) async {
    final pending = Completer<LatLng>();
    final resident = await openLocationForm(
      tester,
      FakeIncidentLocation(() => pending.future),
    );
    await tester.tap(find.text('Use my current location'));
    await tester.pump();
    expect(find.text('Getting your location…'), findsOneWidget);
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    await tester.tap(find.text('Change incident type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fire'));
    await tester.pumpAndSettle();
    pending.complete(const LatLng(14.830123, 120.912345));
    await tester.pumpAndSettle();
    expect(find.textContaining('Latitude:'), findsNothing);
    expect(find.text('Getting your location…'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    resident.dispose();
  });

  testWidgets(
    'resident header omits SOS/call buttons and menu sheet hugs log out without extra gap',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final resident = state(ResidentUiApi());
      await tester.pumpWidget(residentApp(resident));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(FHeader),
          matching: find.text('SOS'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(FHeader),
          matching: find.byIcon(AppIcons.phoneCall),
        ),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('resident-sos-button')), findsOneWidget);
      expect(find.text('Voice calls'), findsNothing);
      await tester.tap(find.byIcon(AppIcons.more));
      await tester.pumpAndSettle();
      expect(find.text('Account & profile'), findsNothing);
      expect(find.text('Search records'), findsOneWidget);
      expect(find.text('Unconfirmed submissions'), findsOneWidget);
      expect(find.text('Refresh information'), findsOneWidget);
      expect(find.text('Community advisories'), findsNothing);
      expect(find.text('Log out'), findsOneWidget);
      final sheetRect = tester.getRect(find.byType(BottomSheet));
      final logoutGroupRect = tester.getRect(
        find.ancestor(
          of: find.text('Log out'),
          matching: find.byType(AppSectionGroup),
        ),
      );
      expect(sheetRect.top, greaterThan(100));
      expect(sheetRect.bottom - logoutGroupRect.bottom, lessThanOrEqualTo(AppSpacing.lg + 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      resident.dispose();
    },
  );

  testWidgets(
    'resident has four clear tabs and can filter reports and read updates',
    (tester) async {
      final api = ResidentUiApi();
      final resident = state(api);
      await tester.pumpWidget(residentApp(resident));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(find.text('Hello, Ana'), findsOneWidget);
      await tester.tap(find.text('Reports').last);
      await tester.pumpAndSettle();
      expect(find.text('RPT-10'), findsOneWidget);
      expect(find.text('RPT-11'), findsOneWidget);
      await tester.tap(find.text('In progress'));
      await tester.pumpAndSettle();
      expect(find.text('RPT-10'), findsOneWidget);
      expect(find.text('RPT-11'), findsNothing);
      await tester.tap(find.text('Updates').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unread'));
      await tester.pumpAndSettle();
      expect(find.text('Report update 1'), findsOneWidget);
      expect(find.text('Report update 2'), findsNothing);
      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();
      expect(api.markedRead, 1);
      expect(resident.unreadCount, 0);
      expect(find.text('You are all caught up'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      resident.dispose();
    },
  );

  testWidgets(
    'resident approval status explains why incident reporting is unavailable',
    (tester) async {
      final resident = state(ResidentUiApi(accepted: false));
      await tester.pumpWidget(residentApp(resident));
      await tester.pumpAndSettle();
      expect(find.text('Account awaiting approval'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('resident-sos-button')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.scrollUntilVisible(
        find.text('Report an incident'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final report = tester.widget<ResidentShortcut>(
        find.widgetWithText(ResidentShortcut, 'Report an incident'),
      );
      expect(report.onTap, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      resident.dispose();
    },
  );

  testWidgets(
    'home SOS calls immediately and report shortcut remains a separate action',
    (tester) async {
      final resident = state(ResidentUiApi());
      var sosCalls = 0, reports = 0, services = 0;
      await tester.pumpWidget(
        residentApp(
          resident,
          child: ResidentHomeScreen(
            onOpenReport: () => reports++,
            onOpenReports: () {},
            onOpenServices: () => services++,
            onSos: () => sosCalls++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Need assistance?'), findsNothing);
      expect(find.text('Request a service'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Request a service')).dy,
        greaterThan(tester.getTopLeft(find.text('Report an incident')).dy),
      );
      final sos = find.byKey(const ValueKey('resident-sos-button'));
      final report = find.text('Report an incident');
      expect(tester.getTopLeft(sos).dy, lessThan(tester.getTopLeft(report).dy));
      final button = tester.widget<FilledButton>(sos);
      expect(button.style!.shape!.resolve({}), isA<CircleBorder>());
      await tester.tap(sos);
      expect(sosCalls, 1);
      expect(reports, 0);
      await tester.tap(report);
      expect(reports, 1);
      await tester.ensureVisible(find.text('Request a service'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request a service'));
      expect(services, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      resident.dispose();
    },
  );

  testWidgets(
    'incident report is a separate flow and unsent details are protected on back',
    (tester) async {
      final resident = state(ResidentUiApi());
      await tester.pumpWidget(residentApp(resident));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report an incident'));
      await tester.pumpAndSettle();
      expect(find.byType(ResidentReportScreen), findsOneWidget);
      expect(find.text('What happened?'), findsOneWidget);
      await tester.tap(find.text('Medical Emergency'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('STEP 2 OF 2 · LOCATION & DETAILS'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Leave this report?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(ResidentReportScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard report'));
      await tester.pumpAndSettle();
      expect(find.byType(ResidentReportScreen), findsNothing);
      expect(find.text('Hello, Ana'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      resident.dispose();
    },
  );

  testWidgets(
    'service requests can be reviewed and cancelled without opening a new form',
    (tester) async {
      final api = ResidentUiApi();
      final resident = state(api);
      await tester.pumpWidget(
        residentApp(resident, child: const ResidentScheduleScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Request #8'), findsOneWidget);
      expect(find.text('Service address'), findsNothing);
      await tester.tap(find.text('Cancel request'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel service request?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel request').last);
      await tester.pumpAndSettle();
      expect(api.cancelled, 8);
      expect(find.text('cancelled'), findsOneWidget);
      await tester.tap(find.text('New request'));
      await tester.pumpAndSettle();
      expect(find.text('Service address'), findsOneWidget);
      final submit = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Send service request'),
      );
      expect(submit.onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      resident.dispose();
    },
  );

  testWidgets(
    'resident screens support compact width and larger text in dark mode',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final resident = state(ResidentUiApi());
      await tester.pumpWidget(residentApp(resident, scale: 1.4, dark: true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Services').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('New request'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Choose a date'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Choose a date'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      resident.dispose();
    },
  );
}
