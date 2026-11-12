import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mdrrmo_flutter/app_prefs.dart';
import 'package:mdrrmo_flutter/main.dart';
import 'package:mdrrmo_flutter/services/auth_service.dart';
import 'package:mdrrmo_flutter/services/internet_connection.dart';
import 'package:mdrrmo_flutter/screens/guest_report_screen.dart';
import 'package:mdrrmo_flutter/screens/login_screen.dart';
import 'package:mdrrmo_flutter/screens/register_screen.dart';
import 'package:mdrrmo_flutter/screens/sos_screen.dart';
import 'package:mdrrmo_flutter/ui/kit.dart';

Widget app(Widget child, {double scale = 1}) {
  final theme = FTheme.neutral.light.touch;
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
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    dotenv.loadFromString(envString: 'API_URL=https://example.test/api');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AppPrefs.init();
  });

  testWidgets(
    'first launch opens unified LoginScreen without role selection or forgot password',
    (tester) async {
      await tester.pumpWidget(
        MdrrmoApp(
          connection: InternetConnection(
            probe: () async => true,
            initiallyOnline: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Welcome to MDRRMO'), findsNothing);
      expect(find.text('Back to role selection'), findsNothing);
      expect(find.text('Forgot password?'), findsNothing);
      expect(find.text('Emergency SOS'), findsOneWidget);
      expect(find.text('Continue as guest'), findsOneWidget);
      expect(find.text('New resident? Create an account'), findsOneWidget);
      expect(
        find.text(
          'Driver and responder accounts are issued by your MDRRMO administrator.',
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('New resident? Create an account'));
      await tester.tap(find.text('New resident? Create an account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RegisterScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        false,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unified LoginScreen opens Emergency SOS and Guest Report', (
    tester,
  ) async {
    await tester.pumpWidget(app(const LoginScreen()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Emergency SOS'));
    await tester.tap(find.text('Emergency SOS'));
    await tester.pumpAndSettle();
    expect(find.byType(SosScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.ensureVisible(find.text('Continue as guest'));
    await tester.tap(find.text('Continue as guest'));
    await tester.pumpAndSettle();
    expect(find.byType(GuestReportPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppPrefs.init clears legacy accountType preference', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'accountType': 'resident'});
    await AppPrefs.init();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('accountType'), isFalse);

    await tester.pumpWidget(
      MdrrmoApp(
        connection: InternetConnection(
          probe: () async => true,
          initiallyOnline: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unified LoginScreen fits a small screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(const LoginScreen(), scale: 1.4));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('New resident? Create an account').hitTestable(),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Sign In'), findsWidgets);
    expect(find.text('New resident? Create an account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unified LoginScreen rejects web-only roles cleanly', (
    tester,
  ) async {
    final service = AuthService(
      client: MockClient(
        (_) async => http.Response(
          '{"token":"staff-token","user":{"id":4,"role":"admin"}}',
          200,
        ),
      ),
    );
    await tester.pumpWidget(app(LoginScreen(authService: service)));
    await tester.pumpAndSettle();

    tester.widget<AppTextField>(find.byType(AppTextField)).controller.text =
        'admin@example.test';
    tester
        .widget<AppPasswordField>(find.byType(AppPasswordField))
        .controller
        .text = 'Password123';

    await tester.tap(find.widgetWithText(AppButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This mobile app is for residents and drivers/responders. Admin and dispatcher accounts use the website.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
