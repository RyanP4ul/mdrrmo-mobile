import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/dispatcher_phone.dart';
import '../services/internet_connection.dart';
import '../services/voice_calls.dart';
import '../ui/kit.dart';
import 'voice_calls_screen.dart';

/// Emergency SOS screen designed with plain, accessible language so anyone
/// can place a regular phone call or a free internet call without guesswork.
/// No authentication, server data, location, or personal details are needed to
/// open the phone dialer.
class SosScreen extends StatefulWidget {
  const SosScreen({
    super.key,
    this.guest = false,
    this.offline = false,
    this.connection,
    this.phoneNumber,
    this.dial,
    this.startSystemCall,
    this.onClose,
  });

  final bool guest;
  final bool offline;
  final InternetConnection? connection;
  final String? phoneNumber;
  final Future<bool> Function(Uri)? dial;
  final Future<void> Function(Map<String, String>)? startSystemCall;
  final VoidCallback? onClose;

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _address = TextEditingController();
  InternetConnection get _connection =>
      widget.connection ?? InternetConnection.instance;
  bool _busy = false;
  String? _error;

  String get _resolvedNumber =>
      (widget.phoneNumber ??
              (DispatcherPhone.number.value.isNotEmpty
                  ? DispatcherPhone.number.value
                  : dotenv.get('DISPATCHER_PHONE', fallback: '')))
          .trim();

  Future<void> _native() async {
    final number = _resolvedNumber;
    if (!RegExp(r'^\+?[0-9][0-9 ()-]{2,24}$').hasMatch(number)) {
      setState(
        () => _error = 'The emergency hotline number is not set up yet.',
      );
      return;
    }
    try {
      final uri = Uri(
        scheme: 'tel',
        path: number.replaceAll(RegExp(r'[ ()-]'), ''),
      );
      final opened =
          await (widget.dial?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!opened) throw StateError('No phone app');
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not open your Phone app. Please dial $number directly.',
        );
      }
    }
  }

  Future<void> _system() async {
    if (_busy || widget.offline) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _connection.check()) {
        if (mounted) {
          setState(
            () => _error =
                'No internet connection right now. Please tap "Call Hotline Now" above instead.',
          );
        }
        return;
      }
      if (!mounted) return;
      final details = <String, String>{
        if (_name.text.trim().isNotEmpty) 'name': _name.text.trim(),
        if (_contact.text.trim().isNotEmpty) 'contact': _contact.text.trim(),
        if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
      };
      if (widget.startSystemCall != null) {
        await widget.startSystemCall!(details);
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VoiceCallsScreen(
              autoStartSos: true,
              voiceFactory: widget.guest
                  ? () => VoiceCallController(
                      api: GuestVoiceCallsApi(details: details),
                      connection: _connection,
                    )
                  : null,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_connection, DispatcherPhone.number]),
      builder: (context, _) {
        final online = !widget.offline && _connection.online;
        final number = _resolvedNumber;
        final canPop = widget.onClose != null || !widget.offline;
        return AppScaffold(
          childPad: false,
          header: pushedHeader(
            context,
            'Emergency SOS',
            onBack: widget.onClose,
            showBack: canPop,
          ),
          child: SafeArea(
            top: false,
            child: ContentFrame(
              maxWidth: 520,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                children: [
                  if (!online) ...[
                    const AppBanner(
                      tone: AppBannerTone.warning,
                      icon: AppIcons.wifiOff,
                      title: 'Offline SOS',
                      message:
                          'No internet right now. You can still call our emergency hotline using your regular phone.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ] else ...[
                    Text(
                      'Need help right away?',
                      style: MdrrmoTypography.displaySm.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap a button below to speak with our emergency team.',
                      style: MdrrmoTypography.bodyMd.copyWith(
                        color: palette.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  _PhoneCallCard(
                    number: number,
                    onCall: _native,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppBanner(
                      tone: AppBannerTone.danger,
                      icon: AppIcons.alert,
                      message: _error!,
                    ),
                  ],
                  if (online) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: Divider(height: 1, color: palette.border),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          child: Text(
                            'OR NO PHONE LOAD?',
                            style: MdrrmoTypography.labelSm.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(height: 1, color: palette.border),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _InternetCallCard(
                      guest: widget.guest,
                      busy: _busy,
                      name: _name,
                      contact: _contact,
                      address: _address,
                      onCall: _system,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const AppBanner(
                      tone: AppBannerTone.info,
                      icon: AppIcons.info,
                      title: 'Not sure which one to choose?',
                      message:
                          'Use "Call Hotline Now" if you have normal phone signal or load. Use "Start Free Internet Call" if you only have Wi-Fi or mobile data.',
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PhoneCallCard extends StatelessWidget {
  const _PhoneCallCard({required this.number, required this.onCall});

  final String number;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Surface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      borderColor: palette.danger.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: palette.dangerTint,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  AppIcons.phoneCall,
                  color: palette.danger,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppStatusBadge(
                      'NO INTERNET NEEDED',
                      color: palette.danger,
                      dot: false,
                      icon: AppIcons.siren,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Call Regular Phone',
                      style: MdrrmoTypography.titleLg.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Opens your phone\'s normal call screen. Works even without Wi-Fi or internet.',
            style: MdrrmoTypography.bodyMd.copyWith(
              color: palette.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: palette.dangerTint.withValues(
                alpha: palette.isDark ? 0.45 : 0.65,
              ),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: palette.danger.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              children: [
                Text(
                  'EMERGENCY HOTLINE',
                  textAlign: TextAlign.center,
                  style: MdrrmoTypography.labelSm.copyWith(
                    color: palette.danger,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  number.isEmpty ? 'Hotline not set up yet' : number,
                  textAlign: TextAlign.center,
                  style: MdrrmoTypography.tabular(
                    MdrrmoTypography.displaySm.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: AppButton(
              label: 'Call Hotline Now',
              icon: AppIcons.phoneCall,
              kind: AppButtonKind.destructive,
              onPress: onCall,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Uses regular mobile signal (carrier call rates may apply).',
            textAlign: TextAlign.center,
            style: MdrrmoTypography.bodySm.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _InternetCallCard extends StatelessWidget {
  const _InternetCallCard({
    required this.guest,
    required this.busy,
    required this.name,
    required this.contact,
    required this.address,
    required this.onCall,
  });

  final bool guest;
  final bool busy;
  final TextEditingController name;
  final TextEditingController contact;
  final TextEditingController address;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Surface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      borderColor: palette.brand.withValues(alpha: 0.28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: palette.brandTint,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  AppIcons.wifi,
                  color: palette.brand,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppStatusBadge(
                      'FREE WITH WI-FI OR DATA',
                      color: palette.brand,
                      dot: false,
                      icon: AppIcons.mic,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Free Internet Call',
                      style: MdrrmoTypography.titleLg.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Talk directly inside this app using Wi-Fi or mobile data. No phone load needed — just keep this screen open.',
            style: MdrrmoTypography.bodyMd.copyWith(
              color: palette.textSecondary,
              height: 1.45,
            ),
          ),
          if (guest) ...[
            const SizedBox(height: AppSpacing.sm),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 8, bottom: 8),
                title: Text(
                  'Add your name & location (optional)',
                  style: MdrrmoTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'Skip this if it\'s urgent — you can call right away.',
                  style: MdrrmoTypography.bodySm.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                children: [
                  AppTextField(
                    controller: name,
                    label: 'Your name',
                    hint: 'e.g. Maria Santos',
                    required: false,
                    maxLength: 120,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: contact,
                    label: 'Your phone number',
                    hint: '09XX XXX XXXX',
                    required: false,
                    maxLength: 40,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: address,
                    label: 'Where are you?',
                    hint: 'House no., street, or barangay',
                    required: false,
                    maxLength: 255,
                    textInputAction: TextInputAction.done,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 54),
            child: AppButton(
              label: busy ? 'Connecting...' : 'Start Free Internet Call',
              icon: AppIcons.mic,
              kind: AppButtonKind.primary,
              loading: busy,
              onPress: busy ? null : onCall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Non-blocking persistent top banner when internet connectivity is lost so
/// active forms and screens stay preserved while offline SOS remains 1 tap away.
class OfflineSosGate extends StatefulWidget {
  const OfflineSosGate({
    super.key,
    required this.child,
    this.connection,
    this.navigatorKey,
  });

  final Widget child;
  final InternetConnection? connection;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<OfflineSosGate> createState() => _OfflineSosGateState();
}

class _OfflineSosGateState extends State<OfflineSosGate> {
  bool _showOverlaySos = false;

  InternetConnection get _source =>
      widget.connection ?? InternetConnection.instance;

  @override
  void initState() {
    super.initState();
    _source.addListener(_onConnection);
  }

  @override
  void didUpdateWidget(covariant OfflineSosGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connection != widget.connection) {
      (oldWidget.connection ?? InternetConnection.instance).removeListener(
        _onConnection,
      );
      _source.addListener(_onConnection);
    }
  }

  void _onConnection() {
    if (_source.online && _showOverlaySos && mounted) {
      setState(() => _showOverlaySos = false);
    }
  }

  @override
  void dispose() {
    _source.removeListener(_onConnection);
    super.dispose();
  }

  void _openOfflineSos() {
    final nav = widget.navigatorKey?.currentState;
    if (nav != null) {
      nav.push(
        MaterialPageRoute<void>(builder: (_) => SosScreen(connection: _source)),
      );
      return;
    }
    setState(() => _showOverlaySos = true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _source,
      builder: (context, _) {
        final offline = _source.hasChecked && !_source.online;
        return Stack(
          children: [
            Column(
              children: [
                if (offline) _OfflineBanner(onOpenSos: _openOfflineSos),
                Expanded(
                  child: offline
                      ? MediaQuery.removePadding(
                          context: context,
                          removeTop: true,
                          child: widget.child,
                        )
                      : widget.child,
                ),
              ],
            ),
            if (offline && _showOverlaySos)
              Positioned.fill(
                child: SosScreen(
                  offline: true,
                  connection: _source,
                  onClose: () => setState(() => _showOverlaySos = false),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.onOpenSos});

  final VoidCallback onOpenSos;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Material(
      color: palette.danger,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              const Icon(AppIcons.wifiOff, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Offline mode — limited connection',
                  style: MdrrmoTypography.labelSm.copyWith(color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: TextButton.icon(
                  onPressed: onOpenSos,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: palette.danger,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  icon: const Icon(AppIcons.phoneCall, size: 15),
                  label: Text(
                    'Offline SOS',
                    style: MdrrmoTypography.labelSm.copyWith(
                      color: palette.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
