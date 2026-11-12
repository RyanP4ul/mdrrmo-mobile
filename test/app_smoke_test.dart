import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mdrrmo_flutter/app_prefs.dart';
import 'package:mdrrmo_flutter/main.dart';
import 'package:mdrrmo_flutter/services/internet_connection.dart';
import 'package:mdrrmo_flutter/screens/login_screen.dart';
import 'package:mdrrmo_flutter/services/auth_service.dart';

void main() {
  testWidgets(
    'startup reaches login and session expiry returns to login',
    (tester) async {
      dotenv.loadFromString(envString: 'API_URL=https://example.test/api');
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await AppPrefs.init();
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

      AuthService.sessionExpired.value++;
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'startup failure is recoverable without crashing or deleting a session',
    (tester) async {
      var attempts = 0;
      dotenv.loadFromString(envString: 'API_URL=https://example.test/api');
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await AppPrefs.init();
      await tester.pumpWidget(
        AppStartup(
          connection: InternetConnection(
            probe: () async => true,
            initiallyOnline: true,
          ),
          initialize: () async {
            attempts++;
            if (attempts == 1) throw StateError('Storage unavailable');
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(attempts, 2);
    },
  );
}
