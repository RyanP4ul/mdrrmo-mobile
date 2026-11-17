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
                'No internet connection right now. Please tap "Call Hotline Now" instead.',
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              child: ContentFrame(
                maxWidth: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!online) ...[
                      const AppBanner(
                        tone: AppBannerTone.warning,
                        icon: AppIcons.wifiOff,
                        title: 'Offline SOS',
                        message:
                            'No internet. Call our hotline with your regular phone.',
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    if (_error != null) ...[
                      AppBanner(
                        tone: AppBannerTone.danger,
                        icon: AppIcons.alert,
                        message: _error!,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    if (online) ...[
                      _InternetCallCard(
                        busy: _busy,
                        onCall: _system,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    _PhoneCallCard(
                      number: number,
                      isAlternative: online,
                      onCall: _native,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PhoneCallCard extends StatelessWidget {
  const _PhoneCallCard({
    required this.number,
    required this.isAlternative,
    required this.onCall,
  });

  final String number;
  final bool isAlternative;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Surface(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      tint: isAlternative ? palette.surfaceSubtle : null,
      borderColor: isAlternative
          ? palette.border
          : palette.danger.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: palette.dangerTint,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(AppIcons.phoneCall, color: palette.danger, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm + 4),
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    Text(
                      'Regular phone call',
                      style: MdrrmoTypography.titleMd.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    AppStatusBadge(
                      isAlternative ? 'Alternative' : 'No internet needed',
                      color: isAlternative ? palette.textMuted : palette.danger,
                      dot: false,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          Text(
            number.isEmpty ? 'Hotline not set up yet' : number,
            style: MdrrmoTypography.tabular(
              MdrrmoTypography.titleLg.copyWith(color: palette.textPrimary),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: AppButton(
              label: 'Call Hotline Now',
              icon: AppIcons.phoneCall,
              kind: isAlternative
                  ? AppButtonKind.dangerOutline
                  : AppButtonKind.destructive,
              onPress: onCall,
            ),
          ),
        ],
      ),
    );
  }
}

class _InternetCallCard extends StatelessWidget {
  const _InternetCallCard({
    required this.busy,
    required this.onCall,
  });

  final bool busy;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Surface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      tint: palette.brandTint.withValues(alpha: palette.isDark ? 0.35 : 0.45),
      borderColor: palette.brand.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: palette.brand,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(AppIcons.mic, color: Colors.white, size: 22),
              ),
              const SizedBox(width: AppSpacing.sm + 4),
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    Text(
                      'Free internet call',
                      style: MdrrmoTypography.titleLg.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    AppStatusBadge(
                      'Wi-Fi / data',
                      color: palette.brand,
                      dot: false,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md + 2),
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
