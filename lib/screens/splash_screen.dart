import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../data/resident_models.dart';
import '../services/auth_service.dart';
import '../services/internet_connection.dart';
import '../ui/kit.dart';
import 'driver-responder/responder_app.dart';
import 'login_screen.dart';
import 'resident/resident_app.dart';
import 'sos_screen.dart';

/// Brand splash: checks existing session immediately and routes to destination.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? _error;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    InternetConnection.instance.addListener(_connectionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_next());
    });
  }

  void _connectionChanged() {
    if (InternetConnection.instance.online && _error != null) {
      unawaited(_next());
    }
  }

  Future<void> _next() async {
    if (_checking || !mounted) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final auth = AuthService();
    Widget? destination;
    try {
      if (await auth.hasToken()) {
        final user = await auth.getMe();
        switch (user['role']) {
          case 'resident':
            destination = ResidentApp(profile: ResidentProfile.fromJson(user));
          case 'driver/responder':
            destination = const ResponderApp();
          default:
            await auth.clearSession();
        }
      }
    } on SessionExpiredException {
      // A rejected token returns to sign-in; connection failures remain retryable.
    } catch (_) {
      if (mounted) {
        setState(() {
          _checking = false;
          _error =
              'Could not check your session. Check your connection and try again.';
        });
      }
      return;
    }
    destination ??= const LoginScreen();
    final next = destination;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => next,
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    InternetConnection.instance.removeListener(_connectionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return AppScaffold(
      childPad: false,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: palette.brandTint,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: palette.brand.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const LogoMark(size: 64),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Balagtas MDRRMO',
                    textAlign: TextAlign.center,
                    style: MdrrmoTypography.displaySm.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Disaster Risk Management & Medical Operations',
                    textAlign: TextAlign.center,
                    style: MdrrmoTypography.bodyMd.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_error != null) ...[
                    AppBanner(
                      tone: AppBannerTone.danger,
                      icon: AppIcons.wifiOff,
                      title: 'Connection error',
                      message: _error!,
                    ),
                    const SizedBox(height: 16),
                    AppButton(label: 'Try again', onPress: _next),
                    const SizedBox(height: 10),
                    AppButton(
                      label: 'Emergency SOS',
                      icon: AppIcons.phoneCall,
                      kind: AppButtonKind.dangerOutline,
                      onPress: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const SosScreen(guest: true),
                        ),
                      ),
                    ),
                  ] else
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: palette.brand,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
