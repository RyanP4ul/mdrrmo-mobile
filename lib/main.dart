import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app_prefs.dart';
import 'services/internet_connection.dart';
import 'services/dispatcher_phone.dart';
import 'screens/sos_screen.dart';
import 'ui/kit.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  runApp(const AppStartup());
}

class AppStartup extends StatefulWidget {
  const AppStartup({super.key, this.initialize, this.connection});
  final InternetConnection? connection;
  final Future<void> Function()? initialize;
  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  bool _ready = false;
  bool _busy = false;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      if (widget.initialize != null) {
        await widget.initialize!();
      } else {
        await dotenv.load();
        await AppPrefs.init();
        await DispatcherPhone.load();
        await AuthService().hasToken();
      }
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _ready
      ? MdrrmoApp(connection: widget.connection)
      : MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.materialLight,
          darkTheme: AppTheme.materialDark,
          themeMode: ThemeMode.system,
          home: Builder(
            builder: (context) {
              final palette = MdrrmoColors.of(context);
              return Scaffold(
                backgroundColor: palette.canvas,
                body: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: palette.brandTint,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                              ),
                              child: const LogoMark(size: 56),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'MDRRMO',
                              style: MdrrmoTypography.displaySm.copyWith(
                                color: palette.brand,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 18),
                            if (_busy)
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: palette.brand,
                                ),
                              ),
                            if (_failed)
                              Surface(
                                borderColor: palette.border,
                                child: Column(
                                  children: [
                                    Icon(
                                      AppIcons.alert,
                                      color: palette.danger,
                                      size: 28,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'The app could not open its settings or secure storage. Try again. Your saved session has not been removed.',
                                      textAlign: TextAlign.center,
                                      style: MdrrmoTypography.bodyMd.copyWith(
                                        color: palette.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    AppButton(
                                      label: 'Try again',
                                      onPress: _start,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
}

class MdrrmoApp extends StatefulWidget {
  const MdrrmoApp({super.key, this.connection});
  final InternetConnection? connection;

  @override
  State<MdrrmoApp> createState() => _MdrrmoAppState();
}

class _MdrrmoAppState extends State<MdrrmoApp> {
  final _navigator = GlobalKey<NavigatorState>();
  InternetConnection get _connection =>
      widget.connection ?? InternetConnection.instance;

  @override
  void initState() {
    super.initState();
    _connection.start();
    AuthService.sessionExpired.addListener(_sessionExpired);
  }

  void _sessionExpired() {
    _navigator.currentState?.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _connection.stop();
    AuthService.sessionExpired.removeListener(_sessionExpired);
    super.dispose();
  }

  static final _light = AppTheme.light;
  static final _dark = AppTheme.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigator,
      title: 'MDRRMO',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        ...FLocalizations.localizationsDelegates,
      ],
      supportedLocales: FLocalizations.supportedLocales,
      theme: AppTheme.materialLight,
      darkTheme: AppTheme.materialDark,
      themeMode: ThemeMode.system,
      builder: (context, child) {
        final isDark = Theme.brightnessOf(context) == Brightness.dark;
        return FTheme(
          data: isDark ? _dark : _light,
          child: FToaster(
            child: OfflineSosGate(
              connection: _connection,
              navigatorKey: _navigator,
              child: FTooltipGroup(child: child ?? const SizedBox.shrink()),
            ),
          ),
        );
      },
      home: const SplashScreen(),
    );
  }
}
