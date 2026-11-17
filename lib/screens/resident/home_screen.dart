import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/resident_models.dart';
import '../../services/dispatcher_phone.dart';
import '../../services/internet_connection.dart';
import '../../services/pending_submissions.dart';
import '../../services/voice_calls.dart';
import '../../state/resident_state.dart';
import '../../ui/kit.dart';
import '../../widgets/res_widgets.dart';
import '../pending_submissions_screen.dart';
import '../record_details_screen.dart';
import 'resident_widgets.dart';

class ResidentHomeScreen extends StatefulWidget {
  const ResidentHomeScreen({
    super.key,
    required this.onOpenReport,
    required this.onOpenReports,
    required this.onOpenServices,
    this.onSos,
    this.connection,
    this.phoneNumber,
    this.dial,
    this.voiceFactory,
    this.enablePulse,
  });

  final VoidCallback onOpenReport, onOpenReports, onOpenServices;
  final VoidCallback? onSos;
  final InternetConnection? connection;
  final String? phoneNumber;
  final Future<bool> Function(Uri)? dial;
  final VoiceCallController Function()? voiceFactory;
  final bool? enablePulse;

  @override
  State<ResidentHomeScreen> createState() => _ResidentHomeScreenState();
}

class _ResidentHomeScreenState extends State<ResidentHomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  VoiceCallController? _voice;
  late final AnimationController _pulseController;
  Timer? _pollTimer;
  Timer? _clockTimer;
  DateTime? _connectedSince;
  VoiceCall? _activeCall;
  String? _sosCallId;
  String? _error;
  bool _busy = false;
  bool _polling = false;
  bool _foreground = true;
  int _pendingSyncCount = 0;

  InternetConnection get _connection =>
      widget.connection ?? InternetConnection.instance;

  String get _resolvedNumber =>
      (widget.phoneNumber ??
              (DispatcherPhone.number.value.isNotEmpty
                  ? DispatcherPhone.number.value
                  : dotenv.get('DISPATCHER_PHONE', fallback: '')))
          .trim();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    PendingSubmissions.changes.addListener(_loadPendingCount);
    unawaited(_loadPendingCount());
  }

  Future<void> _loadPendingCount() async {
    try {
      final list = await PendingSubmissions.read();
      if (mounted) setState(() => _pendingSyncCount = list.length);
    } catch (_) {
      // Storage read failure is surfaced when opening PendingSubmissionsScreen.
    }
  }

  bool get _shouldAnimatePulse {
    if (MediaQuery.disableAnimationsOf(context)) return false;
    if (widget.enablePulse != null) return widget.enablePulse!;
    return !WidgetsBinding.instance.runtimeType.toString().contains(
      'TestWidgetsFlutterBinding',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shouldAnimatePulse) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat();
      }
    } else if (_pulseController.isAnimating) {
      _pulseController.stop();
    }
    if (_voice == null) {
      final approved = ResidentScope.of(context).profile.canSubmit;
      _voice =
          (widget.voiceFactory?.call() ??
                VoiceCallController(
                  api: approved ? VoiceCallsApi() : GuestVoiceCallsApi(),
                  connection: _connection,
                ))
            ..addListener(_voiceChanged);
    }
  }

  void _voiceChanged() {
    final voice = _voice;
    if (voice == null) return;
    final isConnected = voice.phase == VoicePhase.connected;
    if (isConnected && _connectedSince == null) {
      _connectedSince = DateTime.now();
      _clockTimer?.cancel();
      _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!isConnected && voice.phase == VoicePhase.idle) {
      _connectedSince = null;
      _clockTimer?.cancel();
      _clockTimer = null;
    }
    if (mounted) setState(() {});
  }

  String _elapsedText() {
    final started = _connectedSince;
    if (started == null) return '00:00';
    final diff = DateTime.now().difference(started);
    final mins = diff.inMinutes.toString().padLeft(2, '0');
    final secs = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (_voice?.call != null || _sosCallId != null) {
        unawaited(
          _leaveCall('You left the call when the app moved to the background.'),
        );
      }
    }
  }

  Future<void> _startInternetSos() async {
    final voice = _voice;
    if (voice == null || _busy || voice.phase != VoicePhase.idle) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await voice.ensureOnline()) {
        if (mounted) {
          setState(
            () => _error =
                'No internet connection. Tap Call Hotline Now below instead.',
          );
        }
        return;
      }
      if (!mounted) return;
      final call = await voice.api.createSos();
      if (!mounted) {
        await voice.api.end(call.id).catchError((Object _) {});
        return;
      }
      _sosCallId = call.id;
      _activeCall = call;
      if (call.joinable) {
        await voice.join(call);
      }
      _startPolling();
    } catch (error) {
      if (mounted) setState(() => _error = apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_refreshActiveCall()),
    );
  }

  Future<void> _refreshActiveCall() async {
    final voice = _voice;
    final id = _sosCallId;
    if (voice == null ||
        id == null ||
        _polling ||
        !_foreground ||
        !voice.online) {
      return;
    }
    _polling = true;
    try {
      final latest = await voice.api.show(id);
      if (!mounted) return;
      setState(() => _activeCall = latest);
      if (latest.status == 'ended') {
        _pollTimer?.cancel();
        _pollTimer = null;
        _sosCallId = null;
        _activeCall = null;
        await voice.leave();
      }
    } catch (_) {
      /* Transient refresh failures recover on next tick. */
    } finally {
      _polling = false;
    }
  }

  Future<void> _leaveCall([String? message]) async {
    final voice = _voice;
    if (voice == null) return;
    _pollTimer?.cancel();
    _pollTimer = null;
    final id = voice.call?.isSos == true ? voice.call!.id : _sosCallId;
    await voice.leave(message);
    if (id != null) {
      try {
        await voice.api.end(id);
      } catch (error) {
        if (mounted) setState(() => _error = apiErrorMessage(error));
      }
    }
    _sosCallId = null;
    _activeCall = null;
    if (mounted) setState(() {});
  }

  Future<void> _callHotline() async {
    final number = _resolvedNumber;
    if (!RegExp(r'^\+?[0-9][0-9 ()-]{2,24}$').hasMatch(number)) {
      setState(
        () => _error = 'The emergency hotline number is not set up yet.',
      );
      return;
    }
    setState(() => _error = null);
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
              'Could not open your Phone app. Dial $number directly.',
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PendingSubmissions.changes.removeListener(_loadPendingCount);
    _pulseController.dispose();
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    final voice = _voice;
    if (voice != null) {
      voice.removeListener(_voiceChanged);
      final sosId = _sosCallId ??
          (voice.call?.isSos == true ? voice.call!.id : null);
      if (sosId != null) {
        unawaited(voice.api.end(sosId).catchError((Object _) {}));
      }
      voice.dispose();
    }
    super.dispose();
  }

  ReportRecord? _activeReport(ResidentState state) => state.reports
      .where(
        (r) =>
            r.status == IncidentStatus.active ||
            r.status == IncidentStatus.responding,
      )
      .firstOrNull;

  ScheduleRequest? _activeSchedule(ResidentState state) => state.schedules
      .where(
        (s) => const [
          'pending',
          'acknowledged',
          'confirmed',
          'en-route',
          'on-scene',
        ].contains(s.status.toLowerCase()),
      )
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final state = ResidentScope.of(context);
    final palette = MdrrmoColors.of(context);
    final approved = state.profile.canSubmit;
    final firstName = state.profile.firstName.trim();
    final voice = _voice;
    final active = _activeCall ?? voice?.call;
    final phase = voice?.phase ?? VoicePhase.idle;
    final hasActiveCall =
        voice != null && (voice.call != null || phase != VoicePhase.idle);
    final connected =
        phase == VoicePhase.connected || phase == VoicePhase.reconnecting;
    final errorMessage = _error ?? voice?.error;

    final activeReport = _activeReport(state);
    final activeSchedule = activeReport == null ? _activeSchedule(state) : null;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([state.load(), _loadPendingCount()]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          ContentFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ResidentHeading(
                  firstName.isEmpty ? 'Hello' : 'Hello, $firstName',
                ),
                if (!approved) ...[
                  AppBanner(
                    tone: AppBannerTone.warning,
                    icon: AppIcons.info,
                    title: state.profile.registrationStatus == 'declined'
                        ? 'Registration needs attention'
                        : 'Account awaiting approval',
                    message: state.profile.registrationStatus == 'declined'
                        ? 'Contact MDRRMO about your registration.'
                        : 'Reports and service requests unlock once MDRRMO approves your account.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (_pendingSyncCount > 0) ...[
                  AppBanner(
                    tone: AppBannerTone.warning,
                    icon: AppIcons.upload,
                    title:
                        '$_pendingSyncCount unsynced ${_pendingSyncCount == 1 ? 'request' : 'requests'}',
                    message:
                        'Saved on this device and waiting to reach MDRRMO.',
                    action: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              PendingSubmissionsScreen(onRecovered: state.load),
                        ),
                      ),
                      child: const Text('Review & send'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // ── Emergency SOS Pulse & Hotline ──
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: Semantics(
                    label:
                        'SOS. Start an internet call with the dispatcher immediately',
                    button: true,
                    child: SizedBox(
                      width: 212,
                      height: 212,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, _) {
                              final t = Curves.easeOut.transform(
                                _pulseController.value,
                              );
                              return Transform.scale(
                                scale: 1.0 + (0.28 * t),
                                child: Container(
                                  width: 168,
                                  height: 168,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: palette.danger.withValues(
                                      alpha: 0.24 * (1.0 - t),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, _) {
                              final shifted =
                                  (_pulseController.value + 0.5) % 1.0;
                              final t = Curves.easeOut.transform(shifted);
                              return Transform.scale(
                                scale: 1.0 + (0.28 * t),
                                child: Container(
                                  width: 168,
                                  height: 168,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: palette.danger.withValues(
                                        alpha: 0.35 * (1.0 - t),
                                      ),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          SizedBox(
                            width: 168,
                            height: 168,
                            child: FilledButton(
                              key: const ValueKey('resident-sos-button'),
                              style: FilledButton.styleFrom(
                                shape: const CircleBorder(),
                                padding: EdgeInsets.zero,
                                backgroundColor: palette.danger,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: palette.danger
                                    .withValues(alpha: 0.35),
                                disabledForegroundColor: Colors.white,
                                elevation: 0,
                              ),
                              onPressed:
                                  widget.onSos ??
                                  (_busy || hasActiveCall
                                      ? null
                                      : _startInternetSos),
                              child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'SOS',
                                  style: TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Emergency help',
                  textAlign: TextAlign.center,
                  style: MdrrmoTypography.titleLg.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  hasActiveCall
                      ? 'Internet SOS call is active. Keep this screen open.'
                      : 'Tap SOS to start a free internet call with dispatch.',
                  textAlign: TextAlign.center,
                  style: MdrrmoTypography.bodySm.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                if (_busy ||
                    phase == VoicePhase.joining ||
                    phase == VoicePhase.leaving)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.md),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (hasActiveCall) ...[
                  const SizedBox(height: AppSpacing.md),
                  Surface(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    borderColor: palette.danger.withValues(alpha: 0.35),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: AppStatusBadge(
                                switch (phase) {
                                  VoicePhase.joining => 'Connecting...',
                                  VoicePhase.reconnecting => 'Reconnecting...',
                                  VoicePhase.connected =>
                                    !voice.peers.contains(2)
                                        ? 'Calling dispatcher — waiting'
                                        : 'Connected',
                                  VoicePhase.leaving => 'Ending call...',
                                  _ => 'Ready',
                                },
                                color: connected
                                    ? palette.success
                                    : palette.brand,
                              ),
                            ),
                            if (connected && _connectedSince != null)
                              Text(
                                _elapsedText(),
                                style: MdrrmoTypography.tabular(
                                  MdrrmoTypography.labelSm.copyWith(
                                    color: palette.success,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (active != null &&
                            active.isSos &&
                            voice.uid == 1 &&
                            active.queueState != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              switch (active.queueState) {
                                'waiting' =>
                                  'Queued${active.queuePosition == null ? '' : ' (position ${active.queuePosition})'}. Wait or tap Call Hotline Now.',
                                'ringing' =>
                                  'A dispatcher is available. Ringing now.',
                                _ => 'Dispatcher accepted your call.',
                              },
                              style: MdrrmoTypography.bodySm.copyWith(
                                color: palette.textSecondary,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          alignment: WrapAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: connected ? voice.toggleMute : null,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44),
                              ),
                              icon: Icon(
                                voice.muted ? AppIcons.micOff : AppIcons.mic,
                                size: 16,
                              ),
                              label: Text(voice.muted ? 'Unmute' : 'Mute'),
                            ),
                            OutlinedButton.icon(
                              onPressed: connected
                                  ? voice.toggleSpeaker
                                  : null,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44),
                              ),
                              icon: Icon(
                                voice.speaker
                                    ? AppIcons.volumeOn
                                    : AppIcons.volumeOff,
                                size: 16,
                              ),
                              label: Text(
                                voice.speaker ? 'Speaker on' : 'Earpiece',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: phase == VoicePhase.leaving
                                  ? null
                                  : () => _leaveCall(),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                foregroundColor: palette.danger,
                                side: BorderSide(color: palette.danger),
                              ),
                              icon: const Icon(AppIcons.phoneOff, size: 16),
                              label: const Text('End call'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                if (errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppBanner(
                    tone: AppBannerTone.danger,
                    icon: AppIcons.alert,
                    message: errorMessage,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: Divider(height: 1, color: palette.border),
                    ),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        child: Text(
                          'ALTERNATIVE',
                          overflow: TextOverflow.ellipsis,
                          style: MdrrmoTypography.labelSm.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(height: 1, color: palette.border),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  key: const ValueKey('resident-call-hotline-button'),
                  onPressed: _callHotline,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: palette.danger,
                    side: BorderSide(
                      color: palette.danger.withValues(alpha: 0.55),
                    ),
                  ),
                  icon: const Icon(AppIcons.phoneCall, size: 18),
                  label: const Text(
                    'Call Hotline Now',
                    textAlign: TextAlign.center,
                  ),
                ),
                if (_resolvedNumber.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Hotline: $_resolvedNumber · Works without internet',
                    textAlign: TextAlign.center,
                    style: MdrrmoTypography.labelSm.copyWith(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.xl),

                // ── Quick Resident Actions (Grouped List with Divider) ──
                AppSectionGroup(
                  children: [
                    ResidentShortcut(
                      icon: AppIcons.pin,
                      title: 'Report an incident',
                      subtitle: 'Send location and details to MDRRMO',
                      onTap: approved && !state.isSaving
                          ? widget.onOpenReport
                          : null,
                    ),
                    ResidentShortcut(
                      icon: AppIcons.calendar,
                      title: 'Request a service',
                      subtitle: 'Schedule standby or community assistance',
                      onTap: widget.onOpenServices,
                    ),
                  ],
                ),

                // ── Prominent Current Delivery / Incident Status (Shown Once) ──
                if (activeReport != null || activeSchedule != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Current status',
                    style: MdrrmoTypography.titleMd.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (activeReport != null)
                    Surface(
                      padding: const EdgeInsets.all(AppSpacing.md + 2),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RecordDetailsScreen(
                            id: activeReport.id,
                            onChanged: state.load,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          IncidentTile(activeReport.type, soft: true, size: 42),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                statusPill(activeReport.status, context),
                                const SizedBox(height: 6),
                                Text(
                                  activeReport.type.label,
                                  style: MdrrmoTypography.titleMd.copyWith(
                                    color: palette.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  activeReport.location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: MdrrmoTypography.bodySm.copyWith(
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Icon(
                            AppIcons.chevron,
                            size: 18,
                            color: palette.textMuted,
                          ),
                        ],
                      ),
                    )
                  else if (activeSchedule != null)
                    Surface(
                      padding: const EdgeInsets.all(AppSpacing.md + 2),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RecordDetailsScreen(
                            id: activeSchedule.id,
                            schedule: true,
                            onChanged: state.load,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: palette.brand.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Icon(
                              activeSchedule.purpose.icon,
                              size: 20,
                              color: palette.brand,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                residentStatusBadge(
                                  activeSchedule.status,
                                  context,
                                  schedule: true,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  activeSchedule.purpose.label,
                                  style: MdrrmoTypography.titleMd.copyWith(
                                    color: palette.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${fmtDate(activeSchedule.when)} · ${fmtTime(activeSchedule.when)}',
                                  style: MdrrmoTypography.bodySm.copyWith(
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Icon(
                            AppIcons.chevron,
                            size: 18,
                            color: palette.textMuted,
                          ),
                        ],
                      ),
                    ),
                ],

                const SizedBox(height: AppSpacing.xl),
                ResidentHeading(
                  'Recent reports',
                  trailing: TextButton(
                    onPressed: widget.onOpenReports,
                    child: const Text('View all'),
                  ),
                ),
                if (state.reports.isEmpty)
                  const ResidentEmptyState(
                    icon: AppIcons.form,
                    title: 'No reports yet',
                    message:
                        'Submitted reports and updates will appear here.',
                  )
                else
                  AppSectionGroup(
                    children: [
                      for (final report in state.reports.take(3))
                        ResidentReportCard(
                          report: report,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RecordDetailsScreen(
                                id: report.id,
                                onChanged: state.load,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
