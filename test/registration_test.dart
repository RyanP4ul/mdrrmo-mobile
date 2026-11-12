import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mdrrmo_flutter/app_prefs.dart';
import 'package:mdrrmo_flutter/screens/login_screen.dart';
import 'package:mdrrmo_flutter/screens/register_screen.dart';
import 'package:mdrrmo_flutter/services/auth_service.dart';
import 'package:mdrrmo_flutter/ui/kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'unified_login_test.dart' show app;

const policy = {
  'version': 'test-v1',
  'consent': 'I agree to emergency response data processing.',
  'privacy': 'Your emergency records are retained securely.',
};

Future<void> press(WidgetTester tester, String label) async {
  final target = find.text(label);
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> personalDetails(WidgetTester tester) async {
  final fields = tester
      .widgetList<AppTextField>(find.byType(AppTextField))
      .toList();
  fields[0].controller.text = '  Juan   Dela Cruz ';
  fields[1].controller.text = '0912 345 6789';
  fields[2].controller.text = 'Barangay San Juan, Balagtas';
  await press(tester, 'Continue to account');
}

Future<void> accountDetails(WidgetTester tester) async {
  tester.widget<AppTextField>(find.byType(AppTextField)).controller.text =
      'juan@example.test';
  final passwords = tester
      .widgetList<AppPasswordField>(find.byType(AppPasswordField))
      .toList();
  for (final field in passwords) {
    field.controller.text = 'SecurePassword123';
  }
  await press(tester, 'Review my details');
}

void main() {
  setUp(() async {
    dotenv.loadFromString(envString: 'API_URL=https://example.test/api');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AppPrefs.init();
  });

  testWidgets(
    'validates steps, preserves edits, requires consent and submits normalized details',
    (tester) async {
      final requests = <http.Request>[];
      final service = AuthService(
        client: MockClient((request) async {
          requests.add(request);
          return request.method == 'GET'
              ? http.Response(jsonEncode(policy), 200)
              : http.Response(
                  '{"message":"Registration submitted. Your account is waiting for review."}',
                  201,
                );
        }),
      );
      await tester.pumpWidget(app(RegisterScreen(authService: service)));
      await tester.pumpAndSettle();
      await press(tester, 'Continue to account');
      expect(find.text('Full name is required'), findsOneWidget);
      expect(find.text('Home address is required'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await personalDetails(tester);
      final passwords = tester
          .widgetList<AppPasswordField>(find.byType(AppPasswordField))
          .toList();
      tester.widget<AppTextField>(find.byType(AppTextField)).controller.text =
          'invalid';
      passwords[0].controller.text = 'short';
      passwords[1].controller.text = 'different';
      await press(tester, 'Review my details');
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Use at least 8 characters'), findsOneWidget);
      expect(find.text('Passwords do not match'), findsOneWidget);
      await accountDetails(tester);
      expect(find.text('Juan Dela Cruz'), findsOneWidget);
      await press(tester, 'Edit my details');
      expect(
        tester
            .widgetList<AppTextField>(find.byType(AppTextField))
            .first
            .controller
            .text,
        '  Juan   Dela Cruz ',
      );
      await press(tester, 'Continue to account');
      expect(
        tester
            .widgetList<AppPasswordField>(find.byType(AppPasswordField))
            .first
            .controller
            .text,
        'SecurePassword123',
      );
      await press(tester, 'Review my details');
      await press(tester, 'Submit registration');
      await tester.scrollUntilVisible(
        find.text('Please agree to continue'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Please agree to continue'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.scrollUntilVisible(
        find.byType(Checkbox),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.byType(Checkbox)),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await press(tester, 'Submit registration');
      final sent = requests.singleWhere((r) => r.method == 'POST');
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['name'], 'Juan Dela Cruz');
      expect(body['contact'], '09123456789');
      expect(body['address'], 'Barangay San Juan, Balagtas');
      expect(body['password_confirmation'], body['password']);
      expect(body['consent'], true);
      expect(body['consent_version'], 'test-v1');
      expect(sent.headers['Idempotency-Key'], isNotEmpty);
      expect(find.text('Registration submitted'), findsOneWidget);
      await press(tester, 'Continue to sign in');
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'policy failure blocks submission and retry restores consent on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var attempts = 0;
      final service = AuthService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          attempts++;
          return attempts == 1
              ? http.Response('unavailable', 503)
              : http.Response(jsonEncode(policy), 200);
        }),
      );
      await tester.pumpWidget(
        app(RegisterScreen(authService: service), scale: 1.4),
      );
      await tester.pumpAndSettle();
      await personalDetails(tester);
      await accountDetails(tester);
      expect(
        tester
            .widget<AppButton>(
              find.widgetWithText(AppButton, 'Submit registration'),
            )
            .onPress,
        isNull,
      );
      await press(tester, 'Try again');
      await tester.scrollUntilVisible(
        find.byType(Checkbox),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.byType(Checkbox)),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await press(tester, 'Read privacy and retention information');
      expect(find.text(policy['privacy']!), findsOneWidget);
      await press(tester, 'Close');
      await press(tester, 'Reload consent information');
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(attempts, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'server failure preserves details and retry uses the same submission key',
    (tester) async {
      final submissions = <http.Request>[];
      final service = AuthService(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(jsonEncode(policy), 200);
          }
          submissions.add(request);
          return http.Response(
            '{"errors":{"email":["This email address is already registered."]}}',
            422,
          );
        }),
      );
      await tester.pumpWidget(app(RegisterScreen(authService: service)));
      await tester.pumpAndSettle();
      await personalDetails(tester);
      await accountDetails(tester);
      await tester.scrollUntilVisible(
        find.byType(Checkbox),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.byType(Checkbox)),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await press(tester, 'Submit registration');
      expect(
        find.text('This email address is already registered.'),
        findsOneWidget,
      );
      await press(tester, 'Submit registration');
      expect(submissions, hasLength(2));
      expect(
        submissions[0].headers['Idempotency-Key'],
        submissions[1].headers['Idempotency-Key'],
      );
      expect(submissions[0].body, submissions[1].body);
      expect(find.text('juan@example.test'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
