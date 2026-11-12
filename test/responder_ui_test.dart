import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mdrrmo_flutter/data/api/driver_service.api.dart';
import 'package:mdrrmo_flutter/data/models.dart';
import 'package:mdrrmo_flutter/data/paged_records.dart';
import 'package:mdrrmo_flutter/screens/driver-responder/driver_form_screen.dart';
import 'package:mdrrmo_flutter/screens/driver-responder/home_screen.dart';
import 'package:mdrrmo_flutter/screens/driver-responder/history_screen.dart';
import 'package:mdrrmo_flutter/screens/driver-responder/team_screen.dart';
import 'package:mdrrmo_flutter/screens/driver-responder/shell.dart';
import 'package:mdrrmo_flutter/screens/driver-responder/home_assignments_section.dart';
import 'package:mdrrmo_flutter/services/driver_realtime.dart';
import 'package:mdrrmo_flutter/services/driver_tracking.dart';
import 'package:mdrrmo_flutter/state/driver_responder_state.dart';
import 'package:mdrrmo_flutter/ui/app_theme.dart';
import 'package:mdrrmo_flutter/ui/kit.dart' show AppIcons, StepperBar;

class ResponderUiApi extends DriverApi {
  ResponderUiApi({this.assigned = false, this.assignedServices = false})
    : super(Dio());
  final bool assigned;
  final bool assignedServices;
  final Set<int> completedServiceIds = {};
  String availability = 'available';
  String teamRole = 'Driver';
  bool driverTaken = false;
  Completer<void>? roleRequest;
  bool rejectRole = false;
  bool failHistory = false;
  int activeVehicleId = 5;
  List<Map<String, dynamic>> teamVehicles = [
    {
      'id': 5,
      'name': 'Alpha Unit 1',
      'vehicle_type': 'ambulance',
      'vehicle_number': 'RESCUE 01',
      'vehicle_status': 'available',
      'maintenance_warning': 'Brake pads worn - inspect before shift',
    },
    {
      'id': 6,
      'name': 'Alpha Unit 2',
      'vehicle_type': 'ambulance',
      'vehicle_number': 'RESCUE 02',
      'vehicle_status': 'available',
    },
  ];
  Map<String, dynamic>? submittedMaintenance;
  Map<String, dynamic>? savedDriverSection;
  int? savedDriverFormReportId;
  Map<String, dynamic> get roleData => {
    'team_id': 1,
    'team_name': 'Team Alpha',
    'role': teamRole,
    'can_be_driver': !driverTaken,
    'driver_name': driverTaken
        ? 'Maria Santos'
        : (teamRole == 'Driver' ? 'Juan Dela Cruz' : null),
    'locked': assigned,
    'active_vehicle_id': activeVehicleId,
    'active_vehicle': teamVehicles.firstWhere(
      (v) => v['id'] == activeVehicleId,
      orElse: () => teamVehicles.first,
    ),
    'vehicles': teamVehicles,
  };
  @override
  Future<Map<String, dynamic>> switchTeamVehicle(
    int teamId,
    int vehicleId,
  ) async {
    activeVehicleId = vehicleId;
    return {
      'vehicle': roleData['active_vehicle'],
      'team_roles': [roleData],
      'vehicles': teamVehicles,
    };
  }

  @override
  Future<RecordPage> fetchMaintenanceReportsPage({int? before}) async =>
      const RecordPage([], null);

  @override
  Future<Map<String, dynamic>> submitMaintenanceReport(
    Map<String, dynamic> report,
  ) async {
    submittedMaintenance = report;
    return {'id': 99, 'reference': 'MNT-99', ...report};
  }

  @override
  Future<Map<String, dynamic>> updateTeamRole(int teamId, String role) async {
    await roleRequest?.future;
    if (rejectRole) throw StateError('Role change rejected.');
    teamRole = role;
    return {
      'team_roles': [roleData],
      'teams': (await fetchBootstrap())['teams'],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchBootstrap() async => {
    'profile': {
      'name': 'Juan Dela Cruz',
      'vehicle_type': 'ambulance',
      'vehicle_number': 'RESCUE 01',
      'vehicle_status': availability,
      'vehicle_id': 5,
    },
    'teams': [
      {'name': 'Maria Santos', 'role': 'Medic', 'online': true, 'contact': ''},
    ],
    'team_roles': [roleData],
    'can_dispatch': teamRole == 'Driver',
    'incident_types': [],
    'vehicles': [
      {
        'id': 5,
        'vehicle_type': 'ambulance',
        'vehicle_number': 'RESCUE 01',
        'vehicle_status': availability,
      },
    ],
    'assignments': [
      if (assigned)
        {
          'id': 12,
          'reference': 'RPT-12',
          'reported_at': '2026-11-10T08:00:00Z',
          'location': 'Barangay San Juan, Balagtas',
          'type': 'Medical emergency',
          'priority': 'high',
          'vehicle_status': 'available',
          'status': 'dispatched',
          'vehicle_id': 5,
          'patient_name': 'Pedro Penduko',
          'authorized_passenger': 'Pedro Penduko, Maria Santos',
          'lat': 14.82,
          'lng': 120.9,
        },
    ],
  };
  @override
  Future<Map<String, dynamic>> fetchReportForm(int reportId) async => {
    'form': null,
    'revision': 'new',
    'type': 'Medical emergency',
    'defaults': {
      'tripDate': '2026-11-10',
      'driverName': 'Juan Dela Cruz',
      'governmentCardPlateNo': 'RESCUE 01',
      'authorizedPassenger': 'Pedro Penduko, Maria Santos',
      'placeVisitedInspected': 'Barangay San Juan, Balagtas',
      'purpose': 'Emergency Response - Medical emergency',
    },
  };
  @override
  Future<Map<String, dynamic>> saveDriverForm(
    int reportId, {
    required String revision,
    required Map<String, dynamic> driverSection,
  }) async {
    savedDriverFormReportId = reportId;
    savedDriverSection = driverSection;
    return {
      'form': {'driver_section': driverSection},
      'revision': 'rev-2',
    };
  }

  @override
  Future<RecordPage> fetchHistoryPage({int? before}) async {
    if (failHistory) throw StateError('History unavailable.');
    return RecordPage([
      for (final id in [10, 11])
        {
          'id': id,
          'reference': 'RPT-$id',
          'reported_at': '2026-11-04T08:00:00Z',
          'status': id == 10 ? 'resolved' : 'invalid',
          'priority': 'high',
          'type': 'Medical emergency',
          'location': 'Town hall',
        },
    ], null);
  }

  @override
  Future<RecordPage> fetchServiceSchedulesPage({
    int? before,
    bool today = false,
    bool active = false,
  }) async => RecordPage([
    if (assignedServices)
      {
        'id': 42,
        'service_type': 'Ambulance Standby',
        'status': completedServiceIds.contains(42) ? 'completed' : 'confirmed',
        'address': 'Barangay hall',
        'preferred_date': DateTime.now().toIso8601String().substring(0, 10),
        'preferred_time': '09:30',
        'notes': 'Meet at the main entrance.',
        'resident': 'Maria Santos',
        'contact': '09171234567',
        'team_name': 'Team Alpha',
      },
  ], null);
  @override
  Future<void> completeServiceSchedule(int scheduleId) async {
    completedServiceIds.add(scheduleId);
  }

  @override
  Future<String> updateAvailability(String status, {int? vehicleId}) async =>
      availability = status;
}

class MultiAssignmentApi extends ResponderUiApi {
  MultiAssignmentApi() : super(assigned: true, assignedServices: true);
  int? advancedId;
  @override
  Future<Map<String, dynamic>> fetchBootstrap() async {
    final data = await super.fetchBootstrap();
    (data['assignments'] as List).add({
      'id': 13,
      'location': 'Second incident',
      'type': 'Fire response',
      'priority': 'high',
      'vehicle_status': 'en-route',
      'status': 'dispatched',
      'vehicle_id': 5,
    });
    return data;
  }

  @override
  Future<Map<String, dynamic>?> updateAssignmentStatus(
    int reportId,
    String status,
  ) async {
    advancedId = reportId;
    return {
      'id': reportId,
      'location': 'Second incident',
      'type': 'Fire response',
      'priority': 'high',
      'vehicle_status': status,
      'status': 'dispatched',
      'vehicle_id': 5,
    };
  }
}

class ProgressAssignmentApi extends ResponderUiApi {
  ProgressAssignmentApi() : super(assigned: true);
  String responseStatus = 'available';
  final statuses = <String>[];
  bool completed = false;

  Map<String, dynamic> get currentAssignment => {
    'id': 12,
    'location': 'Town hall',
    'type': 'Medical emergency',
    'priority': 'high',
    'status': 'dispatched',
    'vehicle_status': 'available',
    'trip': {
      if (responseStatus != 'available') 'started_at': '2026-11-12T08:00:00Z',
      if (responseStatus == 'on-scene') 'on_scene_at': '2026-11-12T08:10:00Z',
    },
  };

  @override
  Future<Map<String, dynamic>> fetchBootstrap() async => {
    ...await super.fetchBootstrap(),
    'assignments': [if (!completed) currentAssignment],
    'assignment': completed ? null : currentAssignment,
  };

  @override
  Future<Map<String, dynamic>?> updateAssignmentStatus(
    int reportId,
    String status,
  ) async {
    expect(reportId, 12);
    statuses.add(status);
    responseStatus = status;
    completed = status == 'available';
    return completed ? null : currentAssignment;
  }
}

Widget app(Widget child, {double scale = 1, bool dark = false}) {
  final theme = dark ? FTheme.neutral.dark.touch : FTheme.neutral.light.touch;
  final material = theme.toApproximateMaterialTheme();
  return MaterialApp(
    theme: material.copyWith(
      textTheme: material.textTheme.apply(fontFamily: 'Roboto'),
    ),
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
    home: Scaffold(body: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    dotenv.loadFromString(envString: 'API_URL=https://example.test/api');
    final cache = Directory('.tmp/responder-map-cache')
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

  testWidgets(
    'assignment actions stay usable on a narrow screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var advanced = false, details = false;
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ResponderAssignmentCard(
                assignment: Assignment(
                  id: 12,
                  pickup: 'A long incident address, Barangay San Juan, Balagtas, Bulacan',
                  destination: 'District hospital',
                  emergencyType: 'Medical emergency',
                  priority: Priority.high,
                  step: 0,
                ),
                busy: false,
                enabled: true,
                onAdvance: () => advanced = true,
                onDetails: () => details = true,
              ),
            ),
          ),
          scale: 1.5,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Saving update…'), findsNothing);
      await tester.ensureVisible(find.text('Start trip'));
      await tester.tap(find.text('Start trip'));
      expect(advanced, true);
      await tester.ensureVisible(find.text('View report'));
      await tester.tap(find.text('View report'));
      expect(details, true);
      final navigate = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Navigate'),
      );
      expect(navigate.onPressed, isNotNull);
      expect(find.textContaining('No map pin recorded'), findsOneWidget);
    },
  );

  testWidgets(
    'team role replaces vehicle controls and cannot be changed during an active dispatch',
    (tester) async {
      final api = ResponderUiApi();
      final state = ResponderState(api: api);
      await tester.pumpWidget(
        app(ResponderScope(state: state, child: const ResponderTeamScreen())),
      );
      await tester.pumpAndSettle();
      final available = find.byType(SwitchListTile);
      expect(tester.widget<SwitchListTile>(available).value, true);
      await tester.tap(available);
      await tester.pumpAndSettle();
      expect(api.teamRole, 'Responder');
      expect(api.availability, 'available');
      expect(find.text('YOUR VEHICLE'), findsNothing);
      expect(tester.widget<SwitchListTile>(available).value, false);
      await tester.pumpWidget(const SizedBox());
      state.dispose();

      final assigned = ResponderState(api: ResponderUiApi(assigned: true));
      await tester.pumpWidget(
        app(
          ResponderScope(state: assigned, child: const ResponderTeamScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(available).onChanged, isNull);
      expect(find.textContaining('Complete active dispatches'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      assigned.dispose();
    },
  );

  testWidgets(
    'history filters preserve the record links and distinguish outcomes',
    (tester) async {
      final state = ResponderState(api: ResponderUiApi());
      await tester.pumpWidget(
        app(
          ResponderScope(state: state, child: const HistoryScreen()),
          dark: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('RPT-10'), findsOneWidget);
      expect(find.text('RPT-11'), findsOneWidget);
      await tester.tap(find.text('Invalid').first);
      await tester.pumpAndSettle();
      expect(find.text('RPT-10'), findsNothing);
      expect(find.text('RPT-11'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets('team role updates while saving without reloading history', (
    tester,
  ) async {
    final api = ResponderUiApi();
    final state = ResponderState(api: api);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      app(ResponderScope(state: state, child: const ResponderTeamScreen())),
    );
    await tester.pumpAndSettle();
    final toggle = find.byType(SwitchListTile);
    api.roleRequest = Completer<void>();
    api.failHistory = true;
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(toggle).value, false);
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
    api.roleRequest!.complete();
    await tester.pumpAndSettle();
    expect(api.teamRole, 'Responder');
    expect(state.canDispatch, false);
    expect(state.loadError, isNull);
    expect(tester.widget<SwitchListTile>(toggle).value, false);
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNotNull);

    api.roleRequest = null;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, true);
    expect(state.canDispatch, true);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rejected team role restores the previous switch value', (
    tester,
  ) async {
    final api = ResponderUiApi();
    final state = ResponderState(api: api);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      app(ResponderScope(state: state, child: const ResponderTeamScreen())),
    );
    await tester.pumpAndSettle();
    api.roleRequest = Completer<void>();
    api.rejectRole = true;
    final toggle = find.byType(SwitchListTile);
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(toggle).value, false);
    api.roleRequest!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, true);
    expect(state.canDispatch, true);
    expect(state.actionError, isA<StateError>());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('team toggle is disabled when another member is already Driver', (
    tester,
  ) async {
    final api = ResponderUiApi()
      ..teamRole = 'Responder'
      ..driverTaken = true;
    final state = ResponderState(api: api);
    await tester.pumpWidget(
      app(ResponderScope(state: state, child: const ResponderTeamScreen())),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    expect(find.textContaining('Maria Santos is the Driver'), findsOneWidget);
    expect(find.text('YOUR VEHICLE'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('Responder Home hides dispatch cards and start controls', (
    tester,
  ) async {
    final api = ResponderUiApi(assigned: true)..teamRole = 'Responder';
    final state = ResponderState(api: api);
    final realtime = DriverRealtime(client: Dio());
    final tracking = DriverTracking(client: Dio());
    await tester.pumpWidget(
      app(
        ResponderScope(
          state: state,
          child: HomeScreen(realtime: realtime, tracking: tracking),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ResponderAssignmentCard), findsNothing);
    expect(find.byType(HomeAssignmentsSection), findsNothing);
    expect(
      find.textContaining(
        'Dispatches on Home are available to the team Driver',
      ),
      findsOneWidget,
    );
    expect(find.text('Voice calls'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    realtime.dispose();
    tracking.dispose();
  });

  testWidgets(
    'dispatch screen prioritizes the incident and primary action before the map',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ResponderUiApi(assigned: true, assignedServices: true);
      final state = ResponderState(api: api);
      final realtime = DriverRealtime(client: Dio());
      final tracking = DriverTracking(client: Dio());
      await tester.pumpWidget(
        app(
          ResponderScope(
            state: state,
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontFamily: 'Roboto'),
              child: RepaintBoundary(
                child: Material(
                  color: const Color(0xFFF5F7FA),
                  textStyle: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 14,
                    color: Colors.black,
                  ),
                  child: HomeScreen(realtime: realtime, tracking: tracking),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Hello, Juan'), findsOneWidget);
      expect(find.text('Start trip'), findsOneWidget);
      expect(find.text('Assignments'), findsOneWidget);
      expect(find.text('Ambulance Standby'), findsOneWidget);
      final container = find.byKey(
        const ValueKey('home-assignments-container'),
      );
      expect(
        find.descendant(of: container, matching: find.text('Incident #12')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: container,
          matching: find.text('Ambulance Standby'),
        ),
        findsOneWidget,
      );
      expect(find.text('Active assignments'), findsNothing);
      expect(find.text('Scheduled services'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Around you'),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('responder-home-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.getTopLeft(find.text('Start trip')).dy, lessThan(700));
      expect(
        tester.getTopLeft(find.text('Around you')).dy,
        greaterThan(tester.getTopLeft(find.text('Start trip')).dy),
      );
      await tester.scrollUntilVisible(
        find.text('Driver Form'),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('responder-home-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Driver Form'));
      await tester.pumpAndSettle();
      expect(find.text('Authorization'), findsOneWidget);
      expect(find.text('Juan Dela Cruz'), findsOneWidget);
      expect(find.text('Pedro Penduko, Maria Santos'), findsOneWidget);
      expect(find.text('Submit Driver Form'), findsOneWidget);
      final formScrollable = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last;
      await tester.scrollUntilVisible(
        find.text('Fuel'),
        200,
        scrollable: formScrollable,
      );
      expect(find.text('Fuel'), findsOneWidget);
      expect(find.text('Balance in Tank (L) (optional)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      realtime.dispose();
      tracking.dispose();
    },
  );

  testWidgets(
    'assignment button and progress advance together and survive refresh',
    (tester) async {
      final api = ProgressAssignmentApi();
      final state = ResponderState(api: api);
      final realtime = DriverRealtime(client: Dio());
      final tracking = DriverTracking(client: Dio());
      await tester.pumpWidget(
        app(
          ResponderScope(
            state: state,
            child: HomeScreen(realtime: realtime, tracking: tracking),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byKey(const ValueKey('responder-home-list')),
            matching: find.byType(Scrollable),
          )
          .first;
      Future<void> press(String label) async {
        await tester.scrollUntilVisible(
          find.text(label),
          180,
          scrollable: scrollable,
        );
        await Scrollable.ensureVisible(
          tester.element(find.text(label)),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      int currentStep() =>
          tester.widget<StepperBar>(find.byType(StepperBar)).current;
      expect(currentStep(), 0);
      await press('Start trip');
      expect(find.text('Start trip'), findsNothing);
      expect(find.text('Mark as on scene'), findsOneWidget);
      expect(currentStep(), 1);
      await state.load();
      await tester.pumpAndSettle();
      expect(currentStep(), 1);
      await press('Mark as on scene');
      expect(find.text('Mark as on scene'), findsNothing);
      expect(find.text('Complete dispatch'), findsOneWidget);
      expect(currentStep(), 2);
      await state.load();
      await tester.pumpAndSettle();
      expect(currentStep(), 2);
      await press('Complete dispatch');
      expect(find.text('Complete dispatch?'), findsOneWidget);
      await tester.tap(find.text('Complete dispatch').last);
      await tester.pumpAndSettle();
      expect(api.statuses, ['en-route', 'on-scene', 'available']);
      expect(state.assignments, isEmpty);
      expect(find.text('Fill up Driver Form?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      realtime.dispose();
      tracking.dispose();
    },
  );

  testWidgets(
    'unified list advances the selected row when multiple emergency assignments are visible',
    (tester) async {
      final api = MultiAssignmentApi();
      final state = ResponderState(api: api);
      final realtime = DriverRealtime(client: Dio());
      final tracking = DriverTracking(client: Dio());
      await tester.pumpWidget(
        app(
          ResponderScope(
            state: state,
            child: HomeScreen(realtime: realtime, tracking: tracking),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Incident #12'), findsOneWidget);
      expect(find.text('Incident #13'), findsOneWidget);
      expect(state.assignment?.id, 12);
      await tester.scrollUntilVisible(
        find.text('Mark as on scene'),
        250,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('responder-home-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as on scene'));
      await tester.pumpAndSettle();
      expect(api.advancedId, 13);
      expect(state.assignments.firstWhere((item) => item.id == 12).step, 0);
      expect(state.assignments.firstWhere((item) => item.id == 13).step, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      realtime.dispose();
      tracking.dispose();
    },
  );

  testWidgets('scheduled services expose details and road navigation', (
    tester,
  ) async {
    final api = ResponderUiApi(assignedServices: true);
    await tester.pumpWidget(
      app(ListView(children: [HomeAssignmentsSection(api: api)])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Assignments'), findsOneWidget);
    expect(find.text('Ambulance Standby'), findsOneWidget);
    expect(find.text('Barangay hall'), findsOneWidget);
    expect(find.text('Details and progress'), findsOneWidget);
    expect(find.text('Navigate'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'compact responder shell exposes service, team, and history tabs without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = ResponderState(api: ResponderUiApi(assignedServices: true));
      final realtime = DriverRealtime(client: Dio());
      final tracking = DriverTracking(client: Dio());
      await tester.pumpWidget(
        app(
          ResponderScope(
            state: state,
            child: Shell(
              tracking: tracking,
              realtime: realtime,
              onLocationAccessChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(
        find.descendant(
          of: find.byType(FHeader),
          matching: find.byIcon(AppIcons.phoneCall),
        ),
        findsNothing,
      );
      expect(find.text('Voice calls'), findsNothing);
      await tester.tap(find.text('Service').last);
      await tester.pumpAndSettle();
      expect(find.text('Assigned services'), findsOneWidget);
      expect(find.text('Ambulance Standby'), findsOneWidget);
      expect(find.text('Barangay hall'), findsOneWidget);
      expect(find.text('Maria Santos'), findsOneWidget);
      await tester.tap(find.text('Team').last);
      await tester.pumpAndSettle();
      expect(find.text('Your team'), findsOneWidget);
      await tester.tap(find.text('History').last);
      await tester.pumpAndSettle();
      expect(find.text('Dispatch history'), findsOneWidget);
      await tester.tap(find.byIcon(FLucideIcons.ellipsis));
      await tester.pumpAndSettle();
      expect(find.text('Account & profile'), findsOneWidget);
      expect(find.text('My account'), findsNothing);
      expect(find.text('Edit profile'), findsNothing);
      expect(find.text('Change password'), findsNothing);
      expect(find.text('My responder details'), findsNothing);
      expect(find.text('Search records'), findsOneWidget);
      expect(find.text('Announcements and advisories'), findsNothing);
      expect(find.text('Log out'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      realtime.dispose();
      tracking.dispose();
    },
  );

  testWidgets(
    'My Team displays ambulance plate number, maintenance warning, switching, and driver-only maintenance report form',
    (tester) async {
      final api = ResponderUiApi();
      final state = ResponderState(api: api);
      await tester.pumpWidget(
        app(ResponderScope(state: state, child: const ResponderTeamScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Assigned ambulance'), findsOneWidget);
      expect(find.text('Alpha Unit 1'), findsOneWidget);
      expect(find.text('Plate No: RESCUE 01'), findsOneWidget);
      expect(
        find.text('Brake pads worn - inspect before shift'),
        findsOneWidget,
      );
      expect(find.text('Report maintenance'), findsOneWidget);

      await state.switchTeamVehicle(1, 6);
      await tester.pumpAndSettle();
      expect(api.activeVehicleId, 6);
      expect(find.text('Plate No: RESCUE 02'), findsOneWidget);

      await tester.ensureVisible(find.text('Report maintenance'));
      await tester.tap(find.text('Report maintenance'));
      await tester.pumpAndSettle();
      expect(find.text('Driver maintenance report'), findsOneWidget);
      await tester.ensureVisible(find.byType(EditableText).last);
      await tester.enterText(
        find.byType(EditableText).last,
        'Siren amplifier intermittently cuts out during response.',
      );
      await tester.ensureVisible(find.text('Submit maintenance report'));
      await tester.tap(find.text('Submit maintenance report'));
      await tester.pumpAndSettle();
      expect(api.submittedMaintenance?['vehicle_id'], 6);
      expect(
        api.submittedMaintenance?['description'],
        'Siren amplifier intermittently cuts out during response.',
      );

      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'driver form shows validation feedback, recalculates/clears fuel, and recovers from 409 reload',
    (tester) async {
      final api = _ConflictDriverFormApi();
      final state = ResponderState(api: api);
      await state.load();
      addTearDown(state.dispose);

      await tester.pumpWidget(
        app(
          ResponderScope(
            state: state,
            child: const DriverFormScreen(initialReportId: 12),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<Finder> fieldFor(String label, {double delta = 200}) async {
        await tester.scrollUntilVisible(
          find.text(label),
          delta,
          scrollable: find.byType(Scrollable).first,
        );
        return find.descendant(
          of: find.ancestor(
            of: find.text(label),
            matching: find.byType(FTextFormField),
          ),
          matching: find.byType(EditableText),
        );
      }

      // Fuel auto-calculates and clears cleanly when all fuel inputs are cleared
      final balanceField = await fieldFor('Balance in Tank (L) (optional)');
      await tester.enterText(balanceField, '20');
      final usedField = await fieldFor('Fuel Used During Trip (L) (optional)');
      await tester.enterText(usedField, '5');
      await tester.pump();
      expect(find.text('20 L'), findsOneWidget);
      expect(find.text('15 L'), findsOneWidget);

      await tester.enterText(balanceField, '');
      await tester.enterText(usedField, '');
      await tester.pump();
      expect(find.text('20 L'), findsNothing);
      expect(find.text('15 L'), findsNothing);
      expect(find.text('— L'), findsNWidgets(2));

      // Clearing a required field shows an explicit error banner instead of failing silently
      final vehicleField = await fieldFor('Government Vehicle', delta: -200);
      await tester.enterText(vehicleField, '');
      await tester.tap(find.text('Submit Driver Form'));
      await tester.pumpAndSettle();
      expect(
        find.text('Please complete the required fields highlighted below.'),
        findsOneWidget,
      );
      expect(api.savedDriverFormReportId, isNull);

      // Restore valid field -> hits 409 conflict -> user taps Reload Latest Form -> succeeds
      await tester.enterText(vehicleField, 'RESCUE 01');
      await tester.tap(find.text('Submit Driver Form'));
      await tester.pumpAndSettle();
      expect(find.text('Reload Latest Form'), findsOneWidget);

      await tester.tap(find.text('Reload Latest Form'));
      await tester.pumpAndSettle();
      expect(find.text('Reload Latest Form'), findsNothing);

      await tester.tap(find.text('Submit Driver Form'));
      await tester.pumpAndSettle();
      expect(api.savedDriverFormReportId, 12);
      expect(api.savedRevision, 'rev-server-2');
      expect(api.savedDriverSection?['governmentCardPlateNo'], 'RESCUE 01');
    },
  );

  testWidgets(
    'driver form submits cleanly inside FTheme and FToaster without ScaffoldMessenger assertion',
    (tester) async {
      final api = ResponderUiApi(assigned: true);
      final state = ResponderState(api: api);
      await state.load();
      addTearDown(state.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.materialLight,
          builder: (context, child) => FTheme(
            data: AppTheme.light,
            child: FToaster(child: child ?? const SizedBox.shrink()),
          ),
          home: ResponderScope(
            state: state,
            child: const DriverFormScreen(initialReportId: 12),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Submit Driver Form'));
      await tester.pumpAndSettle();
      expect(api.savedDriverFormReportId, 12);
      expect(
        find.text('Driver Form submitted and synced to Website Reports.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _ConflictDriverFormApi extends ResponderUiApi {
  _ConflictDriverFormApi() : super(assigned: true);
  int loadCount = 0;
  int saveAttempts = 0;
  String? savedRevision;

  @override
  Future<Map<String, dynamic>> fetchReportForm(int reportId) async {
    loadCount++;
    return {
      'revision': loadCount >= 2 ? 'rev-server-2' : 'new',
      'form': null,
      'defaults': {
        'tripDate': '2026-11-12',
        'driverName': 'Juan Dela Cruz',
        'governmentCardPlateNo': 'RESCUE 01',
        'authorizedPassenger': 'Ana Reyes',
        'placeVisitedInspected': 'Barangay San Juan, Balagtas',
        'purpose': 'Emergency Response - Medical emergency',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> saveDriverForm(
    int reportId, {
    required String revision,
    required Map<String, dynamic> driverSection,
  }) async {
    saveAttempts++;
    if (revision != 'rev-server-2') {
      throw DioException(
        requestOptions: RequestOptions(
          path: '/driver-responder/reports/$reportId/patient',
        ),
        response: Response(
          requestOptions: RequestOptions(
            path: '/driver-responder/reports/$reportId/patient',
          ),
          statusCode: 409,
          data: {
            'message': 'The patient form changed. Reload it before saving.',
          },
        ),
        type: DioExceptionType.badResponse,
      );
    }
    savedRevision = revision;
    return super.saveDriverForm(
      reportId,
      revision: revision,
      driverSection: driverSection,
    );
  }
}
