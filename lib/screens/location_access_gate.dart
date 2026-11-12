import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:material_ui/material_ui.dart';
import 'package:location/location.dart';

import '../services/driver_tracking.dart';
import '../ui/kit.dart';

enum MapLocationAccess { checking, disabled, denied, permanent, ready, error }

abstract class MapLocationSource {
  Future<bool> enabled();
  Future<PermissionStatus> permission();
  Future<void> enable();
  Future<void> settings(bool serviceDisabled);
  Stream<GpsFix> get positions;
}

class NativeMapLocationSource implements MapLocationSource {
  final _location = Location();

  @override
  Future<bool> enabled() => _location.serviceEnabled();

  @override
  Future<PermissionStatus> permission() => _location.hasPermission();

  @override
  Future<void> enable() async {
    if (!await _location.serviceEnabled()) await _location.requestService();
    if (await _location.serviceEnabled() &&
        await _location.hasPermission() == PermissionStatus.denied) {
      await _location.requestPermission();
    }
  }

  @override
  Future<void> settings(bool serviceDisabled) => AppSettings.openAppSettings(
    type: serviceDisabled ? AppSettingsType.location : AppSettingsType.settings,
  );

  @override
  Stream<GpsFix> get positions => NativeGpsSource().fixes;
}

class MapLocationScope extends InheritedWidget {
  const MapLocationScope({
    super.key,
    required this.position,
    required super.child,
  });

  final GpsFix? position;

  static GpsFix? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MapLocationScope>()?.position;

  @override
  bool updateShouldNotify(MapLocationScope oldWidget) =>
      position != oldWidget.position;
}

class LocationAccessGate extends StatefulWidget {
  const LocationAccessGate({
    super.key,
    required this.child,
    this.source,
    this.onBlocked,
    this.onAccessChanged,
  });

  final Widget child;
  final MapLocationSource? source;
  final Future<void> Function()? onBlocked;
  final ValueChanged<bool>? onAccessChanged;

  @override
  State<LocationAccessGate> createState() => _LocationAccessGateState();
}

class _LocationAccessGateState extends State<LocationAccessGate>
    with WidgetsBindingObserver {
  late final _source = widget.source ?? NativeMapLocationSource();
  MapLocationAccess _access = MapLocationAccess.checking;
  Timer? _timer;
  StreamSubscription<GpsFix>? _positions;
  GpsFix? _position;
  bool _busy = false;
  bool _requesting = false;
  bool _foreground = true;
  bool _hadAccess = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resume();
  }

  void _resume() {
    _foreground = true;
    unawaited(_check());
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_check()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_positions?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _foreground = false;
      if (mounted) setState(() => _access = MapLocationAccess.checking);
      _timer?.cancel();
      unawaited(_positions?.cancel());
      _positions = null;
    }
  }

  Future<void> _check() async {
    if (_busy || !mounted || !_foreground) return;
    _busy = true;
    try {
      var next = MapLocationAccess.disabled;
      if (await _source.enabled()) {
        final permission = await _source.permission();
        next = switch (permission) {
          PermissionStatus.granted ||
          PermissionStatus.grantedLimited => MapLocationAccess.ready,
          PermissionStatus.deniedForever => MapLocationAccess.permanent,
          _ => MapLocationAccess.denied,
        };
      }
      if (!mounted || !_foreground) return;
      final wasReady = _hadAccess;
      _hadAccess = next == MapLocationAccess.ready;
      widget.onAccessChanged?.call(_hadAccess);
      if (next != MapLocationAccess.ready) {
        final positions = _positions;
        _positions = null;
        _position = null;
        setState(() => _access = next);
        unawaited(positions?.cancel());
        if (wasReady) {
          final stopped = widget.onBlocked?.call();
          if (stopped != null) unawaited(stopped.catchError((Object _) {}));
        }
      }
      if (next == MapLocationAccess.ready && _positions == null) {
        _positions = _source.positions.listen(
          (fix) {
            if (mounted && fix.valid(DateTime.now().toUtc())) {
              setState(() => _position = fix);
            }
          },
          onError: (Object _) {
            unawaited(_check());
          },
        );
      }
      if (mounted) {
        setState(() {
          _access = next;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && _foreground) {
        widget.onAccessChanged?.call(false);
        if (_hadAccess) {
          _hadAccess = false;
          final stopped = widget.onBlocked?.call();
          if (stopped != null) unawaited(stopped.catchError((Object _) {}));
        }
        setState(() {
          _access = MapLocationAccess.error;
          _error =
              'Could not check location access. Check device settings and retry.';
        });
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _enable() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      if (_access == MapLocationAccess.permanent) {
        await _source.settings(false);
      } else {
        await _source.enable();
      }
      await _check();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Location access was not enabled. Open settings and allow location.',
        );
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_access == MapLocationAccess.ready) {
      return MapLocationScope(position: _position, child: widget.child);
    }
    if (_access == MapLocationAccess.checking) {
      return const Center(child: CircularProgressIndicator());
    }
    final palette = MdrrmoColors.of(context);
    final serviceEnabled =
        _access != MapLocationAccess.disabled &&
        _access != MapLocationAccess.error;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ContentFrame(
          child: Surface(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: palette.brandTint,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: palette.brand.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Icon(
                      AppIcons.locate,
                      size: 28,
                      color: palette.brand,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _access == MapLocationAccess.disabled
                      ? 'Turn on location to view the map'
                      : 'Allow location access to view the map',
                  style: MdrrmoTypography.titleLg.copyWith(
                    color: palette.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Your GPS location is sent to dispatchers only while signed in and active.',
                  textAlign: TextAlign.center,
                  style: MdrrmoTypography.bodySm.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: palette.surfaceSubtle,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: palette.border),
                  ),
                  child: Column(
                    children: [
                      _ChecklistRow(
                        label: 'Device location services',
                        detail: serviceEnabled ? 'Turned on' : 'Turned off',
                        ready: serviceEnabled,
                      ),
                      Divider(height: AppSpacing.lg, color: palette.border),
                      _ChecklistRow(
                        label: 'MDRRMO location permission',
                        detail: _access == MapLocationAccess.permanent
                            ? 'Allow in phone app settings'
                            : 'Allow while using the app',
                        ready: false,
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppBanner(
                    tone: AppBannerTone.danger,
                    icon: AppIcons.alert,
                    message: _error!,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: _requesting
                      ? 'Checking...'
                      : _access == MapLocationAccess.permanent
                      ? 'Open app settings'
                      : 'Enable location',
                  loading: _requesting,
                  onPress: _requesting ? null : _enable,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.md,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _requesting
                          ? null
                          : () async {
                              try {
                                await _source.settings(
                                  _access == MapLocationAccess.disabled,
                                );
                              } catch (_) {
                                if (context.mounted) {
                                  snack(
                                    context,
                                    'Open your device location settings and allow MDRRMO location access.',
                                  );
                                }
                              }
                            },
                      icon: const Icon(AppIcons.settings, size: 16),
                      label: const Text('Settings'),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _check,
                      icon: const Icon(AppIcons.refresh, size: 16),
                      label: const Text('Check again'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.label,
    required this.detail,
    required this.ready,
  });

  final String label;
  final String detail;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Row(
      children: [
        Icon(
          ready ? AppIcons.checkCircle : AppIcons.infoCircle,
          size: 18,
          color: ready ? palette.success : palette.warningIcon,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: MdrrmoTypography.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              Text(
                detail,
                style: MdrrmoTypography.labelSm.copyWith(
                  fontWeight: FontWeight.w400,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
