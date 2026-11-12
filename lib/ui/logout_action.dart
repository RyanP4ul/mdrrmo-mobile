import 'package:material_ui/material_ui.dart';

import '../services/auth_service.dart';
import '../screens/login_screen.dart';
import 'kit.dart';

bool _logoutBusy = false;
Future<void> logoutFrom(BuildContext context) async {
  if (_logoutBusy) return;
  _logoutBusy = true;
  try {
    final nav = Navigator.of(context);
    final confirmed = await confirmDialog(
      context,
      title: 'Log out?',
      body: 'You will be signed out on this device. Server access is also revoked when the server is reachable. Unconfirmed submissions remain saved for your next sign-in.',
      confirmLabel: 'Log out',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await AuthService().logout();
    if (!context.mounted) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  } catch (error) {
    if (context.mounted) {
      snack(context, 'Could not sign out: ${apiErrorMessage(error)}');
    }
  } finally {
    _logoutBusy = false;
  }
}
