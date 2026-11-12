import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../data/resident_models.dart';
import '../services/auth_service.dart';
import '../ui/kit.dart';
import 'driver-responder/responder_app.dart';
import 'guest_report_screen.dart';
import 'register_screen.dart';
import 'resident/resident_app.dart';
import 'sos_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.authService});

  final AuthService? authService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _key = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  late final AuthService _auth = widget.authService ?? AuthService();

  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();

    if (!_key.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = await _auth.login(
        email: _email.text.trim(),
        password: _password.text,
      );

      final role = user['role']?.toString().toLowerCase();

      final Widget destination;

      switch (role) {
        case 'resident':
          destination = ResidentApp(profile: ResidentProfile.fromJson(user));
          break;
        case 'driver/responder':
          destination = const ResponderApp();
          break;

        default:
          throw Exception(
            'Your account does not have a supported mobile role.',
          );
      }

      if (!mounted) return;

      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => destination));
    } catch (e) {
      if (!mounted) return;

      String message = e.toString();

      if (e is http.ClientException) {
        message = 'Unable to connect to the server. Check your connection.';
      } else if (e is TimeoutException) {
        message = 'The request timed out. Please try again.';
      } else if (e is FormatException) {
        message = 'Invalid response from the server.';
      } else if (e is Exception) {
        message = message.replaceFirst('Exception: ', '');
      }

      setState(() {
        _error = message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);

    return AppScaffold(
      childPad: false,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xl,
            ),
            child: ContentFrame(
              maxWidth: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: palette.brandTint,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: palette.brand.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const LogoMark(size: 56),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'MDRRMO',
                    style: MdrrmoTypography.displaySm.copyWith(
                      color: palette.textPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Disaster Risk Management & Medical Operations',
                    textAlign: TextAlign.center,
                    style: MdrrmoTypography.bodySm.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Surface(
                    padding: const EdgeInsets.all(AppSpacing.lg + 2),
                    child: Form(
                      key: _key,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Sign In',
                            style: MdrrmoTypography.titleLg.copyWith(
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sign in with your resident or responder account.',
                            style: MdrrmoTypography.bodySm.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            AppBanner(
                              tone: AppBannerTone.danger,
                              icon: AppIcons.alert,
                              message: _error!,
                            ),
                          ],
                          const SizedBox(height: 16),
                          AppTextField(
                            controller: _email,
                            label: 'Email address',
                            hint: 'Enter your email',
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            validator: (v) =>
                                RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                    .hasMatch(v!.trim())
                                ? null
                                : 'Enter a valid email address',
                          ),
                          const SizedBox(height: 14),
                          AppPasswordField(
                            controller: _password,
                            onSubmit: _submit,
                          ),
                          const SizedBox(height: 18),
                          AppButton(
                            label: _loading ? 'Signing in...' : 'Sign In',
                            loading: _loading,
                            onPress: _loading ? null : _submit,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppButton(
                    label: 'Emergency SOS',
                    icon: AppIcons.phoneCall,
                    kind: AppButtonKind.dangerOutline,
                    onPress: _loading
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SosScreen(guest: true),
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const GuestReportPage(),
                            ),
                          ),
                    child: const Text('Continue as guest'),
                  ),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RegisterScreen(),
                            ),
                          ),
                    child: const Text('New resident? Create an account'),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Driver and responder accounts are issued by your MDRRMO administrator.',
                      textAlign: TextAlign.center,
                      style: MdrrmoTypography.labelSm.copyWith(
                        color: palette.textMuted,
                        fontWeight: FontWeight.w400,
                      ),
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
