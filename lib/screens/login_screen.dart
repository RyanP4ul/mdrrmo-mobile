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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              palette.brandTint,
                              palette.brand.withValues(
                                alpha: palette.isDark ? 0.22 : 0.12,
                              ),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(
                            color: palette.brand.withValues(alpha: 0.26),
                          ),
                        ),
                        child: const LogoMark(size: 54),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'MDRRMO',
                        style: MdrrmoTypography.displaySm.copyWith(
                          fontSize: 24,
                          color: palette.textPrimary,
                          letterSpacing: 0.8,
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
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Surface(
                    padding: const EdgeInsets.all(AppSpacing.lg + 2),
                    child: Form(
                      key: _key,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Sign In',
                                      style: MdrrmoTypography.titleLg.copyWith(
                                        color: palette.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Sign in with your resident or responder account.',
                                      style: MdrrmoTypography.bodySm.copyWith(
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 38,
                                height: 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: palette.brandTint,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.sm,
                                  ),
                                ),
                                child: Icon(
                                  AppIcons.lock,
                                  size: 18,
                                  color: palette.brand,
                                ),
                              ),
                            ],
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: AppSpacing.md + 2),
                            AppBanner(
                              tone: AppBannerTone.danger,
                              icon: AppIcons.alert,
                              message: _error!,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
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
                          const SizedBox(height: AppSpacing.md + 2),
                          AppPasswordField(
                            controller: _password,
                            onSubmit: _submit,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          AppButton(
                            label: _loading ? 'Signing in...' : 'Sign In',
                            loading: _loading,
                            onPress: _loading ? null : _submit,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Surface(
                    padding: const EdgeInsets.all(AppSpacing.sm + 2),
                    tint: palette.dangerTint,
                    borderColor: palette.danger.withValues(alpha: 0.28),
                    child: AppButton(
                      label: 'Emergency SOS',
                      icon: AppIcons.siren,
                      kind: AppButtonKind.destructive,
                      onPress: _loading
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const SosScreen(guest: true),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppSectionGroup(
                    children: [
                      AppRowItem(
                        leading: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: palette.surfaceSubtle,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(
                            AppIcons.flag,
                            size: 17,
                            color: palette.textSecondary,
                          ),
                        ),
                        title: 'Continue as guest',
                        subtitle: 'Report an emergency without an account',
                        showChevron: true,
                        enabled: !_loading,
                        onTap: _loading
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const GuestReportPage(),
                                ),
                              ),
                      ),
                      AppRowItem(
                        leading: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: palette.brandTint,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(
                            AppIcons.user,
                            size: 17,
                            color: palette.brand,
                          ),
                        ),
                        title: 'New resident? Create an account',
                        subtitle: 'Register for faster tracking and service booking',
                        showChevron: true,
                        enabled: !_loading,
                        onTap: _loading
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
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
