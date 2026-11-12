import 'package:material_ui/material_ui.dart';

import '../data/input_validation.dart';
import '../services/auth_service.dart';
import '../services/pending_submissions.dart' show newSubmissionKey;
import '../ui/form_page.dart';
import '../ui/kit.dart';
import 'login_screen.dart';

/// Resident-only sign-up. Drivers and responders never see this page.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.authService});

  final AuthService? authService;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _scroll = ScrollController(keepScrollOffset: false);
  bool _agreed = false;
  bool _showAgreeError = false;
  bool _loading = false;
  bool _submitted = false;
  String? _error;
  Map<String, dynamic>? _policy;
  bool _policyLoading = false;
  String? _policyError;
  final _submissionKey = newSubmissionKey();
  int _step = 0;
  late final AuthService _auth = widget.authService ?? AuthService();

  void _goToStep(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = step;
      _error = null;
      _showAgreeError = false;
    });
  }

  void _continue() {
    if (_loading) return;
    if (!_key.currentState!.validate()) return;
    _goToStep(_step + 1);
  }

  @override
  void initState() {
    super.initState();
    _loadPolicy();
  }

  Future<void> _loadPolicy() async {
    if (_policyLoading) return;
    setState(() {
      _policyLoading = true;
      _policyError = null;
    });
    try {
      final policy = await _auth.fetchPolicy();
      if (mounted) {
        setState(() {
          _policy = policy;
          _agreed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _policyError = 'Could not load privacy and consent information. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _policyLoading = false);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final c in [_name, _contact, _email, _address, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || _submitted || _policy == null) return;
    FocusScope.of(context).unfocus();
    final valid = _key.currentState!.validate();
    setState(() => _showAgreeError = !_agreed);
    if (!valid || !_agreed) {
      setState(
        () => _error =
            'Review the consent information and agree before submitting.',
      );
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final message = await _auth.register(
        name: InputValidation.normalizeName(_name.text),
        contact: InputValidation.normalizePhone(_contact.text),
        address: _address.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        consentVersion: _policy!['version'] as String,
        submissionKey: _submissionKey,
      );
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _loading = false;
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Registration submitted'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Continue to sign in'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = apiErrorMessage(error));
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showPrivacySheet() {
    if (_policy == null) return;
    final palette = MdrrmoColors.of(context);
    showAppSheet<void>(
      context,
      title: 'Privacy and retention',
      subtitle: 'Consent and emergency record policy',
      builder: (sheetCtx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            _policy!['privacy'] as String,
            style: MdrrmoTypography.bodyMd.copyWith(
              color: palette.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Close',
            onPress: () => Navigator.of(sheetCtx).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);

    return FormPage(
      key: ValueKey(_step),
      scrollController: _scroll,
      title: 'Create resident account',
      formKey: _key,
      submitLabel: _step < 2
          ? (_step == 0 ? 'Continue to account' : 'Review my details')
          : (_loading ? 'Submitting registration...' : 'Submit registration'),
      submitLoading: _loading,
      onSubmit: _loading || _submitted
          ? null
          : (_step < 2 ? _continue : (_policy == null ? null : _submit)),
      children: [
        _introduction(palette),
        if (_step > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _loading ? null : () => _goToStep(_step - 1),
              icon: const Icon(AppIcons.back, size: 16),
              label: const Text('Previous step'),
            ),
          ),
        if (_step == 2 && _policyLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(minHeight: 3),
          ),
        if (_step == 2 && _policyError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppBanner(
              tone: AppBannerTone.warning,
              icon: AppIcons.alert,
              message: _policyError!,
              action: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _loadPolicy,
                  child: const Text('Try again'),
                ),
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppBanner(
              tone: AppBannerTone.danger,
              icon: AppIcons.alert,
              message: _error!,
            ),
          ),
        if (_step == 0)
          FormGroup(
            key: const ValueKey('personal-details'),
            title: 'Your contact details',
            icon: AppIcons.user,
            fields: [
              AppTextField(
                controller: _name,
                maxLength: 120,
                validator: InputValidation.name,
                label: 'Full name',
                hint: 'e.g. Juan Dela Cruz',
                autofillHints: const [AutofillHints.name],
              ),
              AppTextField(
                controller: _contact,
                label: 'Contact number',
                hint: '09XX XXX XXXX',
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                maxLength: 20,
                validator: InputValidation.phone,
              ),
              AppTextField(
                controller: _address,
                label: 'Home address',
                hint: 'House no., street, barangay',
                autofillHints: const [AutofillHints.fullStreetAddress],
                maxLength: 255,
                maxLines: 2,
              ),
            ],
          ),
        if (_step == 1)
          FormGroup(
            key: const ValueKey('account-details'),
            title: 'Secure your account',
            icon: AppIcons.lock,
            fields: [
              AppTextField(
                controller: _email,
                label: 'Email address',
                hint: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: (v) =>
                    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                        .hasMatch((v ?? '').trim())
                    ? null
                    : 'Enter a valid email address',
              ),
              AppPasswordField(
                controller: _password,
                hint: 'Use 8 to 128 characters',
                extraValidator: (value) =>
                    value.runes.length < 8 ? 'Use at least 8 characters' : null,
                textInputAction: TextInputAction.next,
              ),
              AppPasswordField(
                controller: _confirm,
                label: 'Confirm password',
                hint: 'Re-enter your password',
                extraValidator: (v) =>
                    v == _password.text ? null : 'Passwords do not match',
              ),
            ],
          ),
        if (_step == 2) ...[
          _review(palette),
          const SizedBox(height: AppSpacing.lg),
          AppBanner(
            tone: AppBannerTone.info,
            icon: AppIcons.clock,
            message: 'Your registration will be reviewed by MDRRMO. You can sign in after submitting; reports and service requests become available once approved.',
          ),
          const SizedBox(height: AppSpacing.lg),
          Surface(
            padding: const EdgeInsets.all(AppSpacing.md + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(AppIcons.safety, size: 17, color: palette.brand),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your privacy and consent',
                        style: MdrrmoTypography.labelSm.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Semantics(
                  container: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: _policy == null || _loading
                        ? null
                        : () => setState(() {
                            _agreed = !_agreed;
                            _showAgreeError = false;
                          }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _agreed,
                            onChanged: _policy == null || _loading
                                ? null
                                : (v) => setState(() {
                                    _agreed = v ?? false;
                                    _showAgreeError = false;
                                  }),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                _policy?['consent'] as String? ??
                                    'Load the consent information to continue.',
                                style: MdrrmoTypography.bodySm.copyWith(
                                  color: palette.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_showAgreeError)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 4),
                    child: Text(
                      'Please agree to continue',
                      style: MdrrmoTypography.labelSm.copyWith(
                        color: palette.danger,
                      ),
                    ),
                  ),
                if (_policy != null) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _showPrivacySheet,
                        child: const Text(
                          'Read privacy and retention information',
                        ),
                      ),
                      TextButton(
                        onPressed: _loading || _policyLoading
                            ? null
                            : _loadPolicy,
                        child: const Text('Reload consent information'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
        if (_step == 0)
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Already have an account? Sign in'),
          ),
      ],
    );
  }

  Widget _introduction(MdrrmoColors palette) {
    const titles = [
      "Let's get to know you",
      'Create your sign-in details',
      'Review and give consent',
    ];
    const descriptions = [
      'Help MDRRMO reach you with accurate contact and home address details. All fields are required.',
      'Use an email you can access and a password with at least 8 characters.',
      'Check your information before sending it to MDRRMO for review.',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.safety, color: palette.brand, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'RESIDENT REGISTRATION',
                  style: MdrrmoTypography.labelSm.copyWith(
                    color: palette.brand,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= _step ? palette.brand : palette.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Step ${_step + 1} of 3: ${['Personal details', 'Account security', 'Review & consent'][_step]}',
            style: MdrrmoTypography.labelSm.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            titles[_step],
            style: MdrrmoTypography.displaySm.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            descriptions[_step],
            style: MdrrmoTypography.bodyMd.copyWith(
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _review(MdrrmoColors palette) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Your registration details', icon: AppIcons.user),
        for (final entry in {
          'Full name': InputValidation.normalizeName(_name.text),
          'Contact number': InputValidation.normalizePhone(_contact.text),
          'Home address': _address.text.trim(),
          'Email address': _email.text.trim(),
        }.entries) ...[
          Text(
            entry.key,
            style: MdrrmoTypography.labelSm.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            entry.value,
            style: MdrrmoTypography.bodyMd.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        TextButton.icon(
          onPressed: _loading ? null : () => _goToStep(0),
          icon: const Icon(AppIcons.form, size: 16),
          label: const Text('Edit my details'),
        ),
      ],
    ),
  );
}
