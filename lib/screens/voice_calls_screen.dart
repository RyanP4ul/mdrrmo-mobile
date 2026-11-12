import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/internet_connection.dart';
import '../services/voice_calls.dart';
import '../ui/kit.dart';
import 'sos_screen.dart';

/// Available from each participant's app header. Invitations need an open app.
class VoiceCallsButton extends StatefulWidget {
  const VoiceCallsButton({
    super.key,
    this.dispatcher = false,
    this.autoJoin = false,
    this.color,
  });
  final bool dispatcher;
  final bool autoJoin;
  final Color? color;

  @override
  State<VoiceCallsButton> createState() => _VoiceCallsButtonState();
}

class _VoiceCallsButtonState extends State<VoiceCallsButton>
    with WidgetsBindingObserver {
  final _api = VoiceCallsApi();
  Timer? _timer;
  int _count = 0;
  bool _loading = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_load()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading || !_foreground || !InternetConnection.instance.online) return;
    _loading = true;
    try {
      final calls = await _api.list();
      if (mounted) {
        setState(() => _count = calls.where((call) => call.joinable).length);
      }
    } catch (_) {
      /* The calls screen presents service errors and retry controls. */
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? MdrrmoColors.of(context).textPrimary;
    return IconButton(
      color: color,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      tooltip: _count > 0 ? '$_count voice call invitation(s)' : 'Voice calls',
      icon: Badge(
        isLabelVisible: _count > 0,
        label: Text('$_count'),
        child: Icon(AppIcons.phoneCall, color: color, size: 20),
      ),
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VoiceCallsScreen(
              dispatcher: widget.dispatcher,
              autoJoin: widget.autoJoin,
            ),
          ),
        );
        if (mounted) await _load();
      },
    );
  }
}

class VoiceCallsScreen extends StatefulWidget {
  const VoiceCallsScreen({
    super.key,
    this.dispatcher = false,
    this.reportId,
    this.autoStartSos = false,
    this.autoJoin = false,
    this.voiceFactory,
  });

  final bool dispatcher;
  final int? reportId;
  final bool autoStartSos;

  /// Join available calls when a resident deliberately opens this screen.
  final bool autoJoin;
  final VoiceCallController Function()? voiceFactory;

  @override
  State<VoiceCallsScreen> createState() => _VoiceCallsScreenState();
}

class _VoiceCallsScreenState extends State<VoiceCallsScreen>
    with WidgetsBindingObserver {
  late final VoiceCallController _voice;
  List<VoiceCall> _calls = [];
  Timer? _timer;
  Timer? _clockTimer;
  DateTime? _connectedSince;
  String? _error;
  bool _loading = false;
  bool _busy = false;
  bool _foreground = true;
  String? _sosCallId;
  final Set<String> _autoJoinAttempted = {};
  bool _autoJoinStopped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voice = (widget.voiceFactory?.call() ?? VoiceCallController())
      ..addListener(_changed);
    if (widget.autoStartSos) {
      unawaited(_startSos());
    } else {
      unawaited(_load());
    }
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_load()),
    );
  }

  void _changed() {
    final isConnected = _voice.phase == VoicePhase.connected;
    if (isConnected && _connectedSince == null) {
      _connectedSince = DateTime.now();
      _clockTimer?.cancel();
      _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!isConnected && _voice.phase == VoicePhase.idle) {
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
      unawaited(
        _leaveCall('You left the call when the app moved to the background.'),
      );
    }
    if (_foreground) unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading || !_foreground || !_voice.online) return;
    _loading = true;
    try {
      final calls = await _voice.api.list();
      if (mounted) {
        setState(() {
          _calls = calls;
          _error = null;
        });
        await _joinAvailableCall();
      }
    } catch (error) {
      if (mounted) setState(() => _error = apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinAvailableCall() async {
    if (!mounted ||
        !_foreground ||
        _busy ||
        _autoJoinStopped ||
        widget.dispatcher ||
        _voice.phase != VoicePhase.idle) {
      return;
    }
    for (final call in _calls) {
      final requested =
          widget.autoJoin || (widget.autoStartSos && call.id == _sosCallId);
      if (!requested ||
          !call.joinable ||
          call.status != 'active' ||
          !_autoJoinAttempted.add(call.id)) {
        continue;
      }
      if (call.isSos) _sosCallId = call.id;
      await _voice.join(call);
      // A failed attempt stays available for an explicit retry, without
      // repeatedly opening microphone permission prompts on each refresh.
      return;
    }
  }

  Future<void> _startSos() async {
    if (_busy || _voice.phase != VoicePhase.idle) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _voice.ensureOnline() || !mounted) return;
      final call = await _voice.api.createSos();
      if (!mounted) {
        await _voice.api.end(call.id);
        return;
      }
      _sosCallId = call.id;
      _autoJoinStopped = false;
      setState(
        () => _calls = [call, ..._calls.where((item) => item.id != call.id)],
      );
      if (_voice.online && call.joinable) {
        _autoJoinAttempted.add(call.id);
        await _voice.join(call);
      }
    } catch (error) {
      if (mounted) setState(() => _error = apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leaveCall([String? message]) async {
    _autoJoinStopped = true;
    final id = _voice.call?.isSos == true ? _voice.call!.id : _sosCallId;
    await _voice.leave(message);
    if (id != null && !widget.dispatcher) {
      try {
        await _voice.api.end(id);
        _sosCallId = null;
      } catch (error) {
        if (mounted) setState(() => _error = apiErrorMessage(error));
      }
    }
    if (mounted) await _load();
  }

  Future<void> _start() async {
    if (_busy || widget.reportId == null || _voice.phase != VoicePhase.idle) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _voice.ensureOnline() || !mounted) return;
      final call = await _voice.api.create(widget.reportId!);
      if (!mounted) return;
      await _load();
      if (mounted) await _voice.join(call);
    } catch (error) {
      if (mounted) setState(() => _error = apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end(VoiceCall call) async {
    if (_busy) return;
    final confirmed = await confirmDialog(
      context,
      title: 'End this call for everyone?',
      body: 'This will disconnect all participants on this call.',
      confirmLabel: 'End call',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await _voice.api.end(call.id);
      if (_voice.call?.id == call.id) await _voice.leave();
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _clockTimer?.cancel();
    _voice.removeListener(_changed);
    final sosId = !widget.dispatcher
        ? _sosCallId ?? (_voice.call?.isSos == true ? _voice.call!.id : null)
        : null;
    if (sosId != null) {
      unawaited(_voice.api.end(sosId).catchError((Object _) {}));
    }
    _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _voice.call;
    final connected =
        _voice.phase == VoicePhase.connected ||
        _voice.phase == VoicePhase.reconnecting;
    final supported =
        !kIsWeb &&
        {
          TargetPlatform.android,
          TargetPlatform.iOS,
        }.contains(defaultTargetPlatform);
    final palette = MdrrmoColors.of(context);
    final isSosContext = widget.autoStartSos || active?.isSos == true;

    return AppScaffold(
      childPad: false,
      header: pushedHeader(
        context,
        widget.autoStartSos ? 'SOS - Call dispatcher' : 'Voice calls',
      ),
      child: RefreshIndicator(
        onRefresh: _load,
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
                  if (widget.autoStartSos) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          final id = _sosCallId;
                          await _voice.leave();
                          if (id != null) {
                            unawaited(
                              _voice.api.end(id).catchError((Object _) {}),
                            );
                          }
                          if (!context.mounted) return;
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SosScreen(),
                            ),
                          );
                        },
                        icon: const Icon(AppIcons.phone, size: 16),
                        label: const Text('Call regular phone number instead'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  AppBanner(
                    tone: isSosContext
                        ? AppBannerTone.danger
                        : AppBannerTone.info,
                    icon: isSosContext ? AppIcons.siren : AppIcons.phoneCall,
                    title: isSosContext
                        ? 'Resident - Dispatcher SOS call'
                        : 'Resident · Dispatcher · Responder',
                    message: 'Keep this screen open during your call. Allow microphone access when asked.',
                  ),
                  if (!supported) ...[
                    const SizedBox(height: AppSpacing.md),
                    const AppBanner(
                      tone: AppBannerTone.warning,
                      icon: AppIcons.infoCircle,
                      message: 'Use the Android or iOS app for mobile calling, or the MDRRMO website in your browser.',
                    ),
                  ],
                  if (_error != null || _voice.error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppBanner(
                      tone: AppBannerTone.danger,
                      icon: AppIcons.alert,
                      message: _error ?? _voice.error!,
                      action: Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: _load,
                            child: const Text('Refresh calls'),
                          ),
                          TextButton(
                            onPressed: openAppSettings,
                            child: const Text('App permissions'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_busy ||
                      _voice.phase == VoicePhase.joining ||
                      _voice.phase == VoicePhase.leaving)
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpacing.md),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (widget.autoStartSos && _voice.call == null) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      label: _busy
                          ? 'Calling dispatcher...'
                          : _calls.any(
                              (call) => call.id == _sosCallId && call.joinable,
                            )
                          ? 'Retry call'
                          : 'Call dispatcher',
                      icon: AppIcons.siren,
                      kind: AppButtonKind.destructive,
                      loading: _busy,
                      onPress: _busy || !_voice.online ? null : _startSos,
                    ),
                  ],
                  if (widget.dispatcher && widget.reportId != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      label: 'Start call for this report',
                      icon: AppIcons.phoneCall,
                      loading: _busy,
                      onPress:
                          !supported ||
                              !_voice.online ||
                              _busy ||
                              active != null
                          ? null
                          : _start,
                    ),
                  ],
                  if (active != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Surface(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      borderColor: active.isSos
                          ? palette.danger.withValues(alpha: 0.45)
                          : palette.brand.withValues(alpha: 0.4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  active.label,
                                  style: MdrrmoTypography.titleLg.copyWith(
                                    color: palette.textPrimary,
                                  ),
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
                          if (active.isSos &&
                              _voice.uid == 1 &&
                              active.queueState != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                switch (active.queueState) {
                                  'waiting' =>
                                    'Your call is queued${active.queuePosition == null ? '' : ' (position ${active.queuePosition})'}. Calls are handled by emergency priority. You can cancel or use a native phone call.',
                                  'ringing' => 'A dispatcher is available. Your call is ringing now.',
                                  _ => 'The dispatcher accepted your call.',
                                },
                                style: MdrrmoTypography.bodySm.copyWith(
                                  color: palette.textSecondary,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: AppStatusBadge(
                              switch (_voice.phase) {
                                VoicePhase.joining => 'Connecting...',
                                VoicePhase.reconnecting => 'Reconnecting...',
                                VoicePhase.connected =>
                                  active.isSos &&
                                          !_voice.peers.contains(
                                            _voice.uid == 1 ? 2 : 1,
                                          )
                                      ? (_voice.uid == 2
                                            ? 'Waiting for the resident'
                                            : 'Calling dispatcher - waiting for an answer')
                                      : 'Connected',
                                VoicePhase.leaving => 'Leaving...',
                                _ => 'Ready',
                              },
                              color: connected
                                  ? palette.success
                                  : palette.brand,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AppSectionGroup(
                            children: [
                              for (final person in active.participants)
                                AppRowItem(
                                  leading: Icon(
                                    person.uid == _voice.uid ||
                                            _voice.peers.contains(person.uid)
                                        ? AppIcons.checkCircle
                                        : AppIcons.clock,
                                    size: 18,
                                    color:
                                        person.uid == _voice.uid ||
                                            _voice.peers.contains(person.uid)
                                        ? palette.success
                                        : palette.textMuted,
                                  ),
                                  title: person.label,
                                  trailing: Text(
                                    person.uid == _voice.uid
                                        ? 'You'
                                        : _voice.peers.contains(person.uid)
                                        ? 'In call'
                                        : 'Waiting',
                                    style: MdrrmoTypography.labelSm.copyWith(
                                      color: palette.textMuted,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              OutlinedButton.icon(
                                onPressed: connected ? _voice.toggleMute : null,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                ),
                                icon: Icon(
                                  _voice.muted ? AppIcons.micOff : AppIcons.mic,
                                  size: 16,
                                ),
                                label: Text(_voice.muted ? 'Unmute' : 'Mute'),
                              ),
                              OutlinedButton.icon(
                                onPressed: connected
                                    ? _voice.toggleSpeaker
                                    : null,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                ),
                                icon: Icon(
                                  _voice.speaker
                                      ? AppIcons.volumeOn
                                      : AppIcons.volumeOff,
                                  size: 16,
                                ),
                                label: Text(
                                  _voice.speaker ? 'Speaker on' : 'Earpiece',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _voice.phase == VoicePhase.leaving
                                    ? null
                                    : () => _leaveCall(),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                  foregroundColor: palette.danger,
                                  side: BorderSide(
                                    color: palette.danger.withValues(
                                      alpha: 0.45,
                                    ),
                                  ),
                                ),
                                icon: const Icon(AppIcons.phoneOff, size: 16),
                                label: Text(
                                  active.isSos
                                      ? active.queueState == 'waiting' ||
                                                active.queueState == 'ringing'
                                            ? 'Cancel call request'
                                            : 'End SOS call'
                                      : 'Leave',
                                ),
                              ),
                              if (widget.dispatcher)
                                TextButton(
                                  onPressed: _busy ? null : () => _end(active),
                                  child: const Text('End for everyone'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (!widget.autoStartSos) ...[
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Available calls',
                      style: MdrrmoTypography.titleMd.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (_calls.where((call) => call.id != active?.id).isEmpty)
                      const AppStateView(
                        icon: AppIcons.phone,
                        title: 'No other calls',
                        message: 'New dispatcher invitations appear here automatically.',
                      ),
                    for (final call in _calls.where(
                      (call) => call.id != active?.id,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: Surface(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                call.label,
                                style: MdrrmoTypography.titleMd.copyWith(
                                  color: palette.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                call.joinable
                                    ? 'Your three-way call is ready.'
                                    : 'Report changed. The dispatcher needs to start a new call.',
                                style: MdrrmoTypography.bodySm.copyWith(
                                  color: palette.textSecondary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.sm,
                                children: [
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(0, 48),
                                    ),
                                    onPressed:
                                        !supported ||
                                            !_voice.online ||
                                            _busy ||
                                            _voice.phase != VoicePhase.idle ||
                                            !call.joinable
                                        ? null
                                        : () => _voice.join(call),
                                    icon: const Icon(
                                      AppIcons.phoneCall,
                                      size: 16,
                                    ),
                                    label: const Text('Join call'),
                                  ),
                                  if (widget.dispatcher || call.isSos)
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () =>
                                                call.isSos && !widget.dispatcher
                                                ? _leaveCall()
                                                : _end(call),
                                      child: const Text('End call'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
