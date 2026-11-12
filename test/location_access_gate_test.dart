import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:location/location.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mdrrmo_flutter/screens/location_access_gate.dart';
import 'package:mdrrmo_flutter/services/driver_tracking.dart';

class FakeAccess implements MapLocationSource {
  bool service = false;
  PermissionStatus access = PermissionStatus.granted;
  int settingsOpened = 0;
  final updates = StreamController<GpsFix>.broadcast();
  @override
  Future<bool> enabled() async => service;
  @override
  Future<PermissionStatus> permission() async => access;
  @override
  Future<void> enable() async {
    service = true;
    access = PermissionStatus.granted;
  }

  @override
  Future<void> settings(bool serviceDisabled) async {
    settingsOpened++;
  }

  @override
  Stream<GpsFix> get positions => updates.stream;
}

Widget app(Widget child) {
  final theme = FTheme.neutral.light.touch;
  return MaterialApp(
    theme: theme.toApproximateMaterialTheme(),
    builder: (context, child) => FTheme(
      data: theme,
      child: Material(child: child!),
    ),
    home: child,
  );
}

void main() {
  testWidgets(
    'disabled location blocks the map until enabled and hides it again when turned off',
    (tester) async {
      final source = FakeAccess();
      var stopped = 0;
      final accessChanges = <bool>[];
      await tester.pumpWidget(
        app(
          LocationAccessGate(
            source: source,
            onAccessChanged: accessChanges.add,
            onBlocked: () async {
              stopped++;
            },
            child: const Text('Driver map content'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Driver map content'), findsNothing);
      expect(find.text('Turn on location to view the map'), findsOneWidget);
      await tester.tap(find.text('Enable location'));
      await tester.pumpAndSettle();
      expect(find.text('Driver map content'), findsOneWidget);
      expect(accessChanges.last, isTrue);
      source.service = false;
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Driver map content'), findsNothing);
      expect(stopped, 1);
      expect(accessChanges.last, isFalse);
      await tester.pumpWidget(const SizedBox());
      await source.updates.close();
    },
  );
  testWidgets(
    'permanent denial offers settings and keeps the map unavailable',
    (tester) async {
      final source = FakeAccess()
        ..service = true
        ..access = PermissionStatus.deniedForever;
      await tester.pumpWidget(
        app(
          LocationAccessGate(
            source: source,
            child: const Text('Driver map content'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open app settings'));
      await tester.pumpAndSettle();
      expect(source.settingsOpened, 1);
      expect(find.text('Driver map content'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await source.updates.close();
    },
  );
}
