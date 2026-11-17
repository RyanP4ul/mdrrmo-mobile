import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../data/api_client.dart';
import '../data/api/driver_service.api.dart';
import '../data/hospital.dart';
import '../data/models.dart';
import '../services/driver_tracking.dart';
import '../services/incident_location.dart';
import '../services/internet_connection.dart';
import '../services/road_routing.dart';
import '../services/route_navigation.dart';
import '../state/driver_responder_state.dart';
import '../ui/kit.dart';

class RouteNavigationScreen extends StatefulWidget {
  const RouteNavigationScreen({
    super.key,
    required this.address,
    this.destination,
    this.routing,
    this.location,
    this.reportId,
    this.hospitalApi,
    this.responderState,
    this.schedule,
    this.arrivalRadiusMeters,
    this.now,
  });

  final String address;
  final LatLng? destination;
  final RoadRouting? routing;
  final IncidentLocationSource? location;
  final int? reportId;
  final DriverApi? hospitalApi;
  final ResponderState? responderState;
  final ScheduleNavigationInfo? schedule;
  final double? arrivalRadiusMeters;
  final DateTime Function()? now;

  @override
  State<RouteNavigationScreen> createState() => _RouteNavigationScreenState();
}

class _RouteNavigationScreenState extends State<RouteNavigationScreen>
    with WidgetsBindingObserver {
  static const double _defaultArrivalRadiusMeters = 5.0;
  static const double _maxReliableAccuracyMeters = 100.0;
  static const double _offRouteThresholdMeters = 60.0;
  static const Duration _maxFixAge = Duration(seconds: 60);
  static const String _cleanAddressMapStyle =
      '[{"featureType":"poi","stylers":[{"visibility":"off"}]},{"featureType":"transit","stylers":[{"visibility":"off"}]}]';
  static const String _cleanDarkAddressMapStyle =
      '[{"elementType":"geometry","stylers":[{"color":"#1d221f"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#1d221f"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#9ca59e"}]},{"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#d4d8d2"}]},{"featureType":"poi","stylers":[{"visibility":"off"}]},{"featureType":"road","elementType":"geometry","stylers":[{"color":"#2c332f"}]},{"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#202522"}]},{"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9ca59e"}]},{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3b453f"}]},{"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#252b27"}]},{"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#cfd4ce"}]},{"featureType":"transit","stylers":[{"visibility":"off"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#111922"}]},{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#5c7084"}]}]';

  gmaps.GoogleMapController? _mapController;
  final _cancel = CancelToken();
  late final RoadRouting _routing = widget.routing ?? RoadRouting();
  late final IncidentLocationSource _location =
      widget.location ?? DeviceIncidentLocation();
  late final TextEditingController _search = TextEditingController(
    text: widget.address,
  );
  late final DriverApi _hospitalApi = widget.hospitalApi ?? DriverApi();

  Timer? _timer;
  StreamSubscription<GpsFix>? _fixSub;
  LatLng? _origin, _destination, _routeOrigin, _pendingPin;
  RoadRoute? _route;
  List<RouteDestination> _matches = [];
  bool _busy = false,
      _ready = false,
      _foreground = true,
      _searching = false,
      _mapOnly = false,
      _showHospitals = false,
      _showDirections = false,
      _advancingStatus = false,
      _followDriver = true,
      _programmaticCameraMove = false,
      _editingDestination = false;
  late String _scheduleStatus =
      widget.schedule?.status.toLowerCase() ?? 'confirmed';
  double? _heading;
  double? _speedMps;
  int _currentStepIndex = 0;
  DateTime? _lastRerouteAt;
  String? _error, _searchError;
  List<HospitalRecommendation> _hospitals = [];
  bool _loadingHospitals = false;
  String? _hospitalError;
  HospitalRecommendation? _selectedHospital;
  int? _hospitalArrivalPromptId;
  final Set<int> _dismissedHospitalPromptIds = {};

  static gmaps.LatLng _toGmaps(LatLng point) =>
      gmaps.LatLng(point.latitude, point.longitude);

  static LatLng _fromGmaps(gmaps.LatLng point) =>
      LatLng(point.latitude, point.longitude);

  double get _arrivalRadiusMeters {
    final override = widget.arrivalRadiusMeters;
    if (override != null && override.isFinite && override > 0) {
      return override;
    }
    if (dotenv.isInitialized) {
      final parsed = double.tryParse(
        dotenv.env['ARRIVAL_RADIUS_METERS'] ?? '',
      );
      if (parsed != null && parsed.isFinite && parsed > 0) {
        return parsed;
      }
    }
    return _defaultArrivalRadiusMeters;
  }

  Assignment? get _activeAssignment {
    final state = widget.responderState;
    final reportId = widget.reportId;
    if (state == null || reportId == null) return null;
    return state.assignmentById(reportId);
  }

  bool get _showHospitalSuggestions =>
      widget.reportId != null &&
      (_activeAssignment == null || _activeAssignment!.step == 3);

  bool get _isSchedule => widget.schedule != null;

  bool get _isSchedulePickupPhase =>
      _isSchedule &&
      _scheduleStatus != 'on-scene' &&
      _scheduleStatus != 'completed';

  String get _activeAddress {
    final schedule = widget.schedule;
    if (schedule != null) {
      return _isSchedulePickupPhase
          ? schedule.pickupAddress
          : schedule.destinationAddress;
    }
    return widget.address;
  }

  (String, Color) _stageBadge(MdrrmoColors palette, Assignment? assignment) {
    if (_isSchedule) {
      return _isSchedulePickupPhase
          ? ('STEP 1 · PICKUP RESIDENT', palette.brand)
          : ('STEP 2 · TO DESTINATION', palette.success);
    }
    if (_selectedHospital != null) {
      return ('HOSPITAL TRANSPORT', palette.brand);
    }
    return switch (assignment?.step) {
      0 => ('EMERGENCY · ACKNOWLEDGE', palette.danger),
      1 => ('EMERGENCY · EN ROUTE', palette.brand),
      2 => ('EMERGENCY · ON SCENE', palette.success),
      3 => ('EMERGENCY · TRANSPORTING', palette.brand),
      4 => ('EMERGENCY · ARRIVED', palette.success),
      _ => ('EMERGENCY NAVIGATION', palette.brand),
    };
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.responderState?.addListener(_onResponderStateChanged);
    _destination = widget.destination;
    _refresh();
    _startLocationStream();
    if (_showHospitalSuggestions) unawaited(_loadHospitals());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_foreground) unawaited(_refresh(automatic: true));
    });
  }

  void _startLocationStream() {
    final location = _location;
    if (location is! StreamingLocationSource) return;
    _fixSub = location.watchFixes().listen(
      (fix) {
        if (!mounted || !_foreground) return;
        unawaited(_onLiveFix(fix));
      },
      onError: (_) {
        // Periodic timer continues as fallback if live stream errors.
      },
    );
  }

  Future<void> _onLiveFix(GpsFix fix) async {
    final now = (widget.now ?? DateTime.now)();
    final origin = LatLng(fix.latitude, fix.longitude);
    final reliable =
        fix.valid(now) &&
        fix.accuracy <= _maxReliableAccuracyMeters &&
        now.difference(fix.time).abs() <= _maxFixAge;

    setState(() {
      _origin = origin;
      if (fix.heading != null && fix.heading!.isFinite && fix.heading! >= 0) {
        _heading = fix.heading;
      }
      if (fix.speed != null && fix.speed!.isFinite && fix.speed! >= 0) {
        _speedMps = fix.speed;
      }
      _updateStepProgress(origin);
    });

    if (_followDriver && _route != null) {
      await _animateFollowCamera(origin);
    }

    if (_route != null && _destination != null && !_busy) {
      final offRoute = _distanceToRouteMeters(origin, _route!.points);
      final canReroute =
          _lastRerouteAt == null ||
          now.difference(_lastRerouteAt!) >= const Duration(seconds: 8);
      if (offRoute > _offRouteThresholdMeters && canReroute) {
        _lastRerouteAt = now;
        unawaited(_refresh(automatic: true));
      }
    }

    if (reliable) {
      await _evaluateArrival(origin);
    }
  }

  @override
  void didUpdateWidget(covariant RouteNavigationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.responderState != widget.responderState) {
      oldWidget.responderState?.removeListener(_onResponderStateChanged);
      widget.responderState?.addListener(_onResponderStateChanged);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.responderState?.removeListener(_onResponderStateChanged);
    _timer?.cancel();
    _fixSub?.cancel();
    _cancel.cancel();
    if (widget.routing == null) _routing.dispose();
    if (widget.reportId != null && widget.hospitalApi == null) {
      _hospitalApi.dispose();
    }
    _search.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _onResponderStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _animateCamera(gmaps.CameraUpdate update) async {
    final controller = _mapController;
    if (!_ready || controller == null) return;
    _programmaticCameraMove = true;
    try {
      await controller.animateCamera(update);
    } catch (_) {
      // Ignore camera errors if map is disposed mid-flight.
    } finally {
      _programmaticCameraMove = false;
    }
  }

  Future<void> _animateFollowCamera(LatLng origin) async {
    final bearing = _heading ?? _routeBearing(origin, _route) ?? 0.0;
    await _animateCamera(
      gmaps.CameraUpdate.newCameraPosition(
        gmaps.CameraPosition(
          target: _toGmaps(origin),
          zoom: 17.5,
          tilt: 50.0,
          bearing: bearing,
        ),
      ),
    );
  }

  double? _routeBearing(LatLng origin, RoadRoute? route) {
    if (route == null || route.points.length < 2) return null;
    var bestIndex = 0;
    var bestDist = double.infinity;
    const distCalc = Distance();
    for (var i = 0; i < route.points.length - 1; i++) {
      final d = distCalc.as(LengthUnit.Meter, origin, route.points[i]);
      if (d < bestDist) {
        bestDist = d;
        bestIndex = i;
      }
    }
    final next = route.points[math.min(bestIndex + 1, route.points.length - 1)];
    return distCalc.bearing(route.points[bestIndex], next);
  }

  void _fit() {
    if (!_ready || _mapController == null) return;
    if (_followDriver && _route != null && _origin != null) {
      unawaited(_animateFollowCamera(_origin!));
      return;
    }
    final points = [
      ?_origin,
      ?_destination,
      ...?_route?.points,
      if (_showHospitalSuggestions && _selectedHospital == null)
        ..._hospitals.map((hospital) => hospital.point),
    ];
    if (points.isEmpty) return;
    if (points.length == 1) {
      unawaited(
        _animateCamera(
          gmaps.CameraUpdate.newLatLngZoom(_toGmaps(points.first), 16),
        ),
      );
      return;
    }
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final bounds = gmaps.LatLngBounds(
      southwest: gmaps.LatLng(minLat, minLng),
      northeast: gmaps.LatLng(maxLat, maxLng),
    );
    unawaited(_animateCamera(gmaps.CameraUpdate.newLatLngBounds(bounds, 72)));
  }

  void _recenterNavigation() {
    setState(() => _followDriver = true);
    if (_origin != null && _route != null) {
      unawaited(_animateFollowCamera(_origin!));
    } else {
      _fit();
    }
  }

  void _showRouteOverview() {
    setState(() => _followDriver = false);
    final points = [
      ?_origin,
      ?_destination,
      ...?_route?.points,
      if (_showHospitalSuggestions && _selectedHospital == null)
        ..._hospitals.map((hospital) => hospital.point),
    ];
    if (points.length < 2) {
      _fit();
      return;
    }
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    unawaited(
      _animateCamera(
        gmaps.CameraUpdate.newLatLngBounds(
          gmaps.LatLngBounds(
            southwest: gmaps.LatLng(minLat, minLng),
            northeast: gmaps.LatLng(maxLat, maxLng),
          ),
          72,
        ),
      ),
    );
  }

  void _updateStepProgress(LatLng origin) {
    final steps = _route?.steps ?? const [];
    if (steps.isEmpty) {
      _currentStepIndex = 0;
      return;
    }
    const distCalc = Distance();
    var idx = _currentStepIndex.clamp(0, steps.length - 1);
    while (idx < steps.length - 1) {
      final target = steps[idx].endLocation ?? steps[idx + 1].startLocation;
      if (target == null) break;
      final remaining = distCalc.as(LengthUnit.Meter, origin, target);
      if (remaining <= 35) {
        idx++;
      } else {
        break;
      }
    }
    _currentStepIndex = idx;
  }

  double _distanceToRouteMeters(LatLng origin, List<LatLng> points) {
    if (points.isEmpty) return 0;
    const distCalc = Distance();
    var minDist = double.infinity;
    for (final point in points) {
      final d = distCalc.as(LengthUnit.Meter, origin, point);
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  double? _distanceToNextTurnMeters() {
    final steps = _route?.steps ?? const [];
    if (steps.isEmpty || _origin == null) return null;
    final idx = _currentStepIndex.clamp(0, steps.length - 1);
    final step = steps[idx];
    final target =
        step.endLocation ??
        (idx + 1 < steps.length ? steps[idx + 1].startLocation : null);
    if (target != null) {
      return const Distance().as(LengthUnit.Meter, _origin!, target);
    }
    return step.distanceMeters;
  }

  (double, double) _remainingRouteTotals() {
    final route = _route;
    if (route == null) return (0, 0);
    final steps = route.steps;
    if (steps.isEmpty) return (route.distance, route.duration);
    final idx = _currentStepIndex.clamp(0, steps.length - 1);
    if (idx == 0 &&
        (_origin == null ||
            _routeOrigin == null ||
            const Distance().as(LengthUnit.Meter, _origin!, _routeOrigin!) <
                15)) {
      return (route.distance, route.duration);
    }
    double remainingDist =
        _distanceToNextTurnMeters() ?? (steps[idx].distanceMeters ?? 0);
    double remainingDur = steps[idx].durationSeconds ?? 0;
    for (var i = idx + 1; i < steps.length; i++) {
      remainingDist += steps[i].distanceMeters ?? 0;
      remainingDur += steps[i].durationSeconds ?? 0;
    }
    if (remainingDist <= 0) return (route.distance, route.duration);
    if (remainingDur <= 0 && route.distance > 0) {
      remainingDur = route.duration * (remainingDist / route.distance);
    }
    return (remainingDist, remainingDur);
  }

  Future<void> _loadHospitals() async {
    if (_loadingHospitals) return;
    setState(() {
      _loadingHospitals = true;
      _hospitalError = null;
    });
    try {
      final hospitals = await _hospitalApi.fetchHospitals(widget.reportId!);
      if (!mounted) return;
      setState(() => _hospitals = hospitals);
      final assignment = _activeAssignment;
      if (assignment != null &&
          assignment.step == 3 &&
          _selectedHospital == null) {
        final preferred = assignment.hospitalId != null
            ? hospitals
                  .where((h) => h.id == assignment.hospitalId && h.isAvailable)
                  .firstOrNull
            : null;
        final next =
            preferred ?? hospitals.where((h) => h.isAvailable).firstOrNull;
        if (next != null) {
          setState(() {
            _selectedHospital = next;
            _destination = next.point;
            _route = null;
            _routeOrigin = null;
            _pendingPin = null;
            _showHospitals = false;
          });
          if (!_busy) {
            await _refresh();
          }
          return;
        }
      }
      _fit();
    } catch (_) {
      if (mounted) {
        setState(
          () => _hospitalError = 'Could not load recommended hospitals.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingHospitals = false);
    }
  }

  Future<void> _selectHospital(HospitalRecommendation? hospital) async {
    if (_busy) return;
    setState(() {
      _selectedHospital = hospital;
      _destination = hospital?.point ?? widget.destination;
      _route = null;
      _routeOrigin = null;
      _pendingPin = null;
      _showHospitals = false;
      if (hospital == null || _hospitalArrivalPromptId != hospital.id) {
        _hospitalArrivalPromptId = null;
      }
    });
    await _refresh();
  }

  Future<void> _refresh({bool automatic = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final now = (widget.now ?? DateTime.now)();
      late final LatLng origin;
      var reliableForArrival = false;
      final location = _location;
      if (location is DetailedLocationSource) {
        final fix = await location.currentFix();
        origin = LatLng(fix.latitude, fix.longitude);
        if (fix.heading != null && fix.heading!.isFinite && fix.heading! >= 0) {
          _heading = fix.heading;
        }
        if (fix.speed != null && fix.speed!.isFinite && fix.speed! >= 0) {
          _speedMps = fix.speed;
        }
        reliableForArrival =
            fix.valid(now) &&
            fix.accuracy <= _maxReliableAccuracyMeters &&
            now.difference(fix.time).abs() <= _maxFixAge;
      } else {
        origin = await _location.current();
      }
      if (!mounted) return;
      setState(() {
        _origin = origin;
        _updateStepProgress(origin);
      });
      final destination = _destination;
      if (destination != null &&
          (!automatic ||
              _route == null ||
              _routeOrigin == null ||
              const Distance().as(LengthUnit.Meter, _routeOrigin!, origin) >=
                  40)) {
        final route = await _routing.route(
          origin,
          destination,
          cancelToken: _cancel,
        );
        if (!mounted) return;
        setState(() {
          _route = route;
          _routeOrigin = origin;
          _currentStepIndex = 0;
          _updateStepProgress(origin);
        });
      }
      if (!automatic) _fit();
      if (reliableForArrival) {
        await _evaluateArrival(origin);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _route = null;
        _error = error is IncidentLocationException
            ? 'Enable device location and allow location access, then update the route.'
            : error is StateError
            ? error.message.toString()
            : 'Could not load a road route. Check your connection and destination, then try again.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _evaluateArrival(LatLng origin) async {
    final target = _selectedHospital?.point ?? _destination;
    if (target == null) return;
    final distanceMeters = const Distance().as(
      LengthUnit.Meter,
      origin,
      target,
    );
    if (distanceMeters > _arrivalRadiusMeters) return;

    final selectedHospital = _selectedHospital;
    final assignment = _activeAssignment;
    if (selectedHospital != null) {
      if (_dismissedHospitalPromptIds.contains(selectedHospital.id)) return;
      if (!selectedHospital.isAvailable) return;
      if (assignment == null || assignment.step == 3) {
        setState(() => _hospitalArrivalPromptId = selectedHospital.id);
      }
      return;
    }

    if (assignment != null && assignment.step == 1 && !_advancingStatus) {
      await _advanceDispatch(expectedStep: 1, automatic: true);
    }
  }

  Future<void> _markSelectedHospitalUnavailable() async {
    final state = widget.responderState;
    final reportId = widget.reportId;
    final hospital = _selectedHospital;
    if (state == null || reportId == null || hospital == null || _advancingStatus) {
      return;
    }
    setState(() => _advancingStatus = true);
    try {
      final updatedHospitals = await state.markHospitalUnavailable(
        reportId,
        hospital.id,
      );
      if (!mounted) return;
      final next = updatedHospitals.where((h) => h.isAvailable).firstOrNull;
      setState(() {
        _hospitals = updatedHospitals;
        _hospitalArrivalPromptId = null;
      });
      await _selectHospital(next);
      if (!mounted) return;
      snack(
        context,
        next != null
            ? '${hospital.name} marked not available. Routing to ${next.name}.'
            : '${hospital.name} marked not available. No other available hospitals.',
      );
    } catch (error) {
      if (mounted) snack(context, apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _advancingStatus = false);
    }
  }

  Future<void> _advanceDispatch({
    required int expectedStep,
    bool automatic = false,
    bool skipConfirm = false,
  }) async {
    final state = widget.responderState;
    final reportId = widget.reportId;
    if (state == null || reportId == null || _advancingStatus) return;
    final current = state.assignmentById(reportId);
    if (current == null || current.step != expectedStep) return;

    int? hospitalId;
    String? destination;
    HospitalRecommendation? targetHospital;

    if (expectedStep == 2) {
      if (_hospitals.isEmpty) {
        await _loadHospitals();
        if (!mounted) return;
      }
      targetHospital =
          (_selectedHospital != null && _selectedHospital!.isAvailable)
          ? _selectedHospital
          : _hospitals.where((h) => h.isAvailable).firstOrNull;
      if (targetHospital == null) {
        snack(
          context,
          'No available hospital found. Check recommended hospitals or contact dispatch.',
        );
        return;
      }
      hospitalId = targetHospital.id;
      destination = targetHospital.name;
    }

    if (expectedStep == 3) {
      final activeHospital = _selectedHospital;
      if (activeHospital == null || !activeHospital.isAvailable) {
        snack(
          context,
          'Arrived requires an available hospital. Select or skip to an available hospital.',
        );
        return;
      }
      hospitalId = activeHospital.id;
      destination = activeHospital.name;
      if (!skipConfirm) {
        final confirmed = await confirmDialog(
          context,
          title: 'Arrived at ${activeHospital.name}?',
          body:
              'This confirms arrival at the hospital and moves the dispatch to History.',
          confirmLabel: 'Arrived',
        );
        if (!confirmed || !mounted) return;
      }
    }

    setState(() => _advancingStatus = true);
    try {
      final advanced = await state.advanceAssignmentFor(
        reportId,
        expectedStep: expectedStep,
        hospitalId: hospitalId,
        destination: destination,
      );
      if (!mounted) return;
      if (advanced) {
        if (expectedStep == 0) {
          snack(context, 'Dispatch acknowledged — En Route.');
        } else if (expectedStep == 1) {
          snack(
            context,
            automatic
                ? 'Arrived at incident (within 5 m) — status updated to On Scene.'
                : 'Marked as On Scene.',
          );
        } else if (expectedStep == 2) {
          if (targetHospital != null) {
            await _selectHospital(targetHospital);
          }
          if (!mounted) return;
          snack(
            context,
            'Transporting patient to ${targetHospital?.name ?? 'hospital'}.',
          );
        } else {
          setState(() => _hospitalArrivalPromptId = null);
          snack(context, 'Arrived at hospital. Dispatch saved to History.');
          state.requestDispatchTab();
          final nav = Navigator.of(context);
          if (nav.canPop()) {
            nav.popUntil((route) => route.isFirst);
          }
        }
      } else if (!automatic && state.actionError != null) {
        snack(context, '${state.actionError}');
      }
    } finally {
      if (mounted) setState(() => _advancingStatus = false);
    }
  }

  Future<void> _advanceScheduleStatus() async {
    final schedule = widget.schedule;
    if (schedule == null || _advancingStatus) return;
    final next = switch (_scheduleStatus) {
      'confirmed' => 'en-route',
      'en-route' => 'on-scene',
      _ => 'completed',
    };
    if (next == 'completed') {
      final confirmed = await confirmDialog(
        context,
        title: 'Complete service?',
        body:
            'Mark this scheduled service as completed? The resident and your team will be notified.',
        confirmLabel: 'Complete service',
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _advancingStatus = true);
    try {
      await dio.patch(
        '/driver-responder/schedules/${schedule.scheduleId}/status',
        data: {'status': next},
        cancelToken: _cancel,
      );
      if (!mounted) return;
      setState(() => _scheduleStatus = next);
      if (schedule.onStatusUpdated != null) {
        unawaited(schedule.onStatusUpdated!.call().catchError((Object _) {}));
      }
      if (next == 'en-route') {
        snack(context, 'Trip started. Heading to pickup address.');
      } else if (next == 'on-scene') {
        final dest = schedule.destinationAddress.trim();
        setState(() {
          _destination = null;
          _route = null;
          _routeOrigin = null;
          _pendingPin = null;
          _currentStepIndex = 0;
          _matches = [];
          _searchError = null;
          _search.text = dest;
          _editingDestination = dest.isEmpty;
        });
        if (dest.isNotEmpty) {
          snack(context, 'Resident picked up! Routing to destination…');
          unawaited(_refresh());
        } else {
          snack(
            context,
            'Resident picked up! Search or pin the destination, or tap Complete Service.',
          );
        }
      } else {
        snack(context, 'Service completed.');
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    } catch (error) {
      if (mounted) snack(context, apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _advancingStatus = false);
    }
  }

  Future<void> _findDestination() async {
    if (_searching || _search.text.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await _routing.search(
        _search.text,
        near: _origin,
        cancelToken: _cancel,
      );
      if (!mounted) return;
      setState(() {
        _matches = results;
        if (results.isEmpty) {
          _searchError =
              'No matching address. Refine the address or long-press the map to place the destination pin.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _searchError =
              'Address search unavailable. Try again or long-press the map to place the destination pin.',
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _preview(LatLng point) {
    if (_busy) return;
    setState(() {
      _pendingPin = point;
      _matches = [];
      _followDriver = false;
    });
    if (_ready) {
      unawaited(
        _animateCamera(
          gmaps.CameraUpdate.newLatLngZoom(_toGmaps(point), 16),
        ),
      );
    }
  }

  Future<void> _confirmDestination() async {
    if (_pendingPin == null || _busy) return;
    setState(() {
      _destination = _pendingPin;
      _pendingPin = null;
      _route = null;
      _followDriver = true;
      _editingDestination = false;
    });
    await _refresh();
  }

  IconData _maneuverIcon(RouteStep? step) {
    if (step == null) return AppIcons.navigation;
    final type = step.maneuverType;
    final mod = step.modifier;
    if (type.contains('arrive')) return Icons.flag_rounded;
    if (mod.contains('left')) {
      return mod.contains('sharp') || mod.contains('uturn')
          ? Icons.turn_sharp_left_rounded
          : mod.contains('slight')
          ? Icons.turn_slight_left_rounded
          : Icons.turn_left_rounded;
    }
    if (mod.contains('right')) {
      return mod.contains('sharp') || mod.contains('uturn')
          ? Icons.turn_sharp_right_rounded
          : mod.contains('slight')
          ? Icons.turn_slight_right_rounded
          : Icons.turn_right_rounded;
    }
    if (type.contains('roundabout') || type.contains('rotary')) {
      return Icons.roundabout_right_rounded;
    }
    return Icons.straight_rounded;
  }

  String _formatDistance(double meters) => meters >= 1000
      ? '${(meters / 1000).toStringAsFixed(1)} km'
      : '${meters.round()} m';

  Widget _floatingMapButton({
    required MdrrmoColors palette,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        side: BorderSide(color: palette.border),
      ),
      child: IconButton(
        tooltip: tooltip,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: onPressed,
        icon: Icon(icon, color: palette.textPrimary, size: 20),
      ),
    );
  }

  Set<gmaps.Polyline> _buildPolylines(MdrrmoColors palette) {
    final route = _route;
    if (route == null || route.points.length < 2) return const {};
    final gPoints = route.points.map(_toGmaps).toList(growable: false);
    return {
      gmaps.Polyline(
        polylineId: const gmaps.PolylineId('route_outline'),
        points: gPoints,
        width: 10,
        color: Colors.white,
        jointType: gmaps.JointType.round,
        startCap: gmaps.Cap.roundCap,
        endCap: gmaps.Cap.roundCap,
        zIndex: 1,
      ),
      gmaps.Polyline(
        polylineId: const gmaps.PolylineId('route_main'),
        points: gPoints,
        width: 6,
        color: palette.brand,
        jointType: gmaps.JointType.round,
        startCap: gmaps.Cap.roundCap,
        endCap: gmaps.Cap.roundCap,
        zIndex: 2,
      ),
    };
  }

  Set<gmaps.Marker> _buildMarkers() {
    final markers = <gmaps.Marker>{};
    if (_showHospitalSuggestions) {
      for (final hospital in _hospitals) {
        final selected = _selectedHospital?.id == hospital.id;
        markers.add(
          gmaps.Marker(
            markerId: gmaps.MarkerId('hospital_${hospital.id}'),
            position: _toGmaps(hospital.point),
            icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
              selected
                  ? gmaps.BitmapDescriptor.hueAzure
                  : gmaps.BitmapDescriptor.hueCyan,
            ),
            infoWindow: gmaps.InfoWindow(
              title: hospital.name,
              snippet: '${hospital.distanceKm.toStringAsFixed(1)} km away',
            ),
            onTap: _busy || _mapOnly ? null : () => _selectHospital(hospital),
          ),
        );
      }
    }
    if (_origin != null) {
      markers.add(
        gmaps.Marker(
          markerId: const gmaps.MarkerId('driver_origin'),
          position: _toGmaps(_origin!),
          flat: true,
          rotation: _heading ?? _routeBearing(_origin!, _route) ?? 0.0,
          anchor: const Offset(0.5, 0.5),
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueBlue,
          ),
          infoWindow: const gmaps.InfoWindow(title: 'Your current location'),
          zIndexInt: 3,
        ),
      );
    }
    if (_destination != null) {
      markers.add(
        gmaps.Marker(
          markerId: const gmaps.MarkerId('destination'),
          position: _toGmaps(_destination!),
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueRed,
          ),
          infoWindow: const gmaps.InfoWindow(title: 'Destination'),
          zIndexInt: 2,
        ),
      );
    }
    if (_pendingPin != null) {
      markers.add(
        gmaps.Marker(
          markerId: const gmaps.MarkerId('pending_pin'),
          position: _toGmaps(_pendingPin!),
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueOrange,
          ),
          infoWindow: const gmaps.InfoWindow(title: 'Confirm this destination'),
          zIndexInt: 2,
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final assignment = _activeAssignment;
    final activeAddress = _activeAddress;
    final destinationTitle =
        _selectedHospital?.name ??
        (activeAddress.isEmpty
            ? (_isSchedule && !_isSchedulePickupPhase
                  ? 'Set drop-off destination'
                  : 'Assigned destination')
            : activeAddress);
    final showSearch =
        _editingDestination ||
        (_destination == null && _selectedHospital == null);
    final allowLongPressPin =
        (widget.destination == null || _editingDestination) &&
        _selectedHospital == null;
    final stage = _stageBadge(palette, assignment);
    final steps = _route?.steps ?? const [];
    final safeIdx = steps.isEmpty
        ? 0
        : _currentStepIndex.clamp(0, steps.length - 1);
    final nextStep = steps.isNotEmpty ? steps[safeIdx] : null;
    final followingStep =
        safeIdx + 1 < steps.length ? steps[safeIdx + 1] : null;
    final showHospitalPrompt =
        !_mapOnly &&
        _selectedHospital != null &&
        _hospitalArrivalPromptId == _selectedHospital!.id &&
        (assignment == null || assignment.step == 3);
    final speedKmh = _speedMps != null && _speedMps!.isFinite
        ? (_speedMps! * 3.6).round()
        : null;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 480;
          return Stack(
            children: [
              // ── Full-bleed Google Map (kept mounted so map-only mode never resets camera) ──
              Positioned.fill(
                child: gmaps.GoogleMap(
                  initialCameraPosition: gmaps.CameraPosition(
                    target: _toGmaps(
                      widget.destination ?? const LatLng(14.82, 120.90),
                    ),
                    zoom: 14,
                  ),
                  trafficEnabled: true,
                  buildingsEnabled: true,
                  style: palette.isDark
                      ? _cleanDarkAddressMapStyle
                      : _cleanAddressMapStyle,
                  compassEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  polylines: _buildPolylines(palette),
                  markers: _buildMarkers(),
                  padding: EdgeInsets.only(
                    top: _mapOnly ? 0 : (compact ? 96 : 132),
                    bottom: _mapOnly ? 0 : (compact ? 110 : 148),
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    _ready = true;
                    _fit();
                  },
                  onCameraMoveStarted: () {
                    if (!_programmaticCameraMove && _followDriver) {
                      setState(() => _followDriver = false);
                    }
                  },
                  onTap: (_) => setState(() => _mapOnly = !_mapOnly),
                  onLongPress: allowLongPressPin && !_mapOnly
                      ? (point) => _preview(_fromGmaps(point))
                      : null,
                ),
              ),

              if (_mapOnly)
                Positioned(
                  bottom: AppSpacing.lg,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    top: false,
                    child: Center(
                      child: FilledButton.icon(
                        onPressed: () => setState(() => _mapOnly = false),
                        icon: const Icon(Icons.layers_rounded, size: 18),
                        label: const Text('Show controls'),
                      ),
                    ),
                  ),
                ),

              if (!_mapOnly) ...[
                // ── Top Waze-style turn banner / destination header ──
                Positioned(
                  top: compact ? AppSpacing.xs : AppSpacing.sm,
                  left: AppSpacing.md,
                  right: AppSpacing.md,
                  child: SafeArea(
                    bottom: false,
                    child: ContentFrame(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_route != null && !showSearch)
                            _buildTurnBanner(
                              context,
                              palette: palette,
                              nextStep: nextStep,
                              followingStep: followingStep,
                              canAdjustPin: allowLongPressPin,
                            )
                          else
                            _buildSearchOrStatusHeader(
                              context,
                              palette: palette,
                              destinationTitle: destinationTitle,
                              needsSearch: showSearch,
                              compact: compact,
                              stageLabel: stage.$1,
                              stageColor: stage.$2,
                            ),
                          ListenableBuilder(
                            listenable: InternetConnection.instance,
                            builder: (context, _) {
                              final offline =
                                  InternetConnection.instance.hasChecked &&
                                  !InternetConnection.instance.online;
                              if (!offline) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.xs,
                                ),
                                child: Material(
                                  color: palette.warningTint,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.sm,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          AppIcons.wifiOff,
                                          size: 15,
                                          color: palette.warningIcon,
                                        ),
                                        const SizedBox(width: AppSpacing.xs),
                                        Expanded(
                                          child: Text(
                                            'Offline — status & route sync paused',
                                            style: MdrrmoTypography.labelSm
                                                .copyWith(
                                                  color: palette.warning,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Material(
                              color: palette.dangerTint,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: AppSpacing.xs,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      AppIcons.alert,
                                      size: 16,
                                      color: palette.danger,
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: MdrrmoTypography.bodySm.copyWith(
                                          color: palette.danger,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (_route != null && speedKmh != null)
                                _buildSpeedometerBadge(
                                  palette: palette,
                                  speedKmh: speedKmh,
                                )
                              else
                                const SizedBox.shrink(),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (!_followDriver && _route != null) ...[
                                    FilledButton.icon(
                                      onPressed: _recenterNavigation,
                                      icon: const Icon(
                                        Icons.my_location_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Re-center'),
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                  ],
                                  _floatingMapButton(
                                    palette: palette,
                                    icon: AppIcons.locate,
                                    tooltip: 'Show route',
                                    onPressed: _showRouteOverview,
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  _floatingMapButton(
                                    palette: palette,
                                    icon: AppIcons.refresh,
                                    tooltip: 'Update route',
                                    onPressed: _busy ? null : () => _refresh(),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Bottom navigation panel + hospital arrival prompt ──
                if (compact)
                  Positioned.fill(
                    child: SafeArea(
                      top: false,
                      child: ContentFrame(
                        child: DraggableScrollableSheet(
                          initialChildSize: 0.38,
                          minChildSize: 0.24,
                          maxChildSize: 0.82,
                          expand: true,
                          builder: (ctx, scrollController) => Material(
                            color: palette.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(AppRadius.lg),
                              ),
                              side: BorderSide(color: palette.border),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: SingleChildScrollView(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.md,
                                AppSpacing.xs,
                                AppSpacing.md,
                                AppSpacing.md,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Center(
                                    child: Container(
                                      width: 36,
                                      height: 4,
                                      margin: const EdgeInsets.only(
                                        bottom: AppSpacing.xs,
                                      ),
                                      decoration: BoxDecoration(
                                        color: palette.borderStrong,
                                        borderRadius: BorderRadius.circular(
                                          AppRadius.pill,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (showHospitalPrompt) ...[
                                    _buildHospitalArrivalPrompt(
                                      palette: palette,
                                      hospital: _selectedHospital!,
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                  ],
                                  _buildBottomPanelContent(
                                    context,
                                    palette: palette,
                                    assignment: assignment,
                                    destinationTitle: destinationTitle,
                                    compact: compact,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      child: ContentFrame(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (showHospitalPrompt)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.md,
                                  0,
                                  AppSpacing.md,
                                  AppSpacing.sm,
                                ),
                                child: _buildHospitalArrivalPrompt(
                                  palette: palette,
                                  hospital: _selectedHospital!,
                                ),
                              ),
                            _buildBottomPanel(
                              context,
                              palette: palette,
                              assignment: assignment,
                              destinationTitle: destinationTitle,
                              compact: compact,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSpeedometerBadge({
    required MdrrmoColors palette,
    required int speedKmh,
  }) {
    return Material(
      color: palette.surface.withValues(alpha: 0.96),
      shape: const CircleBorder(),
      elevation: 4,
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: palette.border, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$speedKmh',
              style: MdrrmoTypography.tabular(
                MdrrmoTypography.titleMd.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              ),
            ),
            Text(
              'km/h',
              style: MdrrmoTypography.bodySm.copyWith(
                fontSize: 10,
                color: palette.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTurnBanner(
    BuildContext context, {
    required MdrrmoColors palette,
    required RouteStep? nextStep,
    required RouteStep? followingStep,
    required bool canAdjustPin,
  }) {
    final stepDistance = _distanceToNextTurnMeters() ?? nextStep?.distanceMeters;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: palette.brand,
          borderRadius: followingStep != null
              ? const BorderRadius.vertical(top: Radius.circular(AppRadius.md))
              : BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _maneuverIcon(nextStep),
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (stepDistance != null)
                        Text(
                          _formatDistance(stepDistance),
                          style: MdrrmoTypography.tabular(
                            MdrrmoTypography.titleLg.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                        ),
                      Text(
                        nextStep?.instruction ?? 'Follow route',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MdrrmoTypography.bodyMd.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canAdjustPin)
                  IconButton(
                    tooltip: 'Adjust destination pin',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: () => setState(() {
                      _editingDestination = true;
                      _search.text = _activeAddress;
                    }),
                    icon: const Icon(
                      AppIcons.edit,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (followingStep != null)
          Material(
            color: const Color(0xFF0F172A),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(AppRadius.md),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 6,
              ),
              child: Row(
                children: [
                  Text(
                    'Then',
                    style: MdrrmoTypography.bodySm.copyWith(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    _maneuverIcon(followingStep),
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      followingStep.instruction,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MdrrmoTypography.bodySm.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchOrStatusHeader(
    BuildContext context, {
    required MdrrmoColors palette,
    required String destinationTitle,
    required bool needsSearch,
    required bool compact,
    required String stageLabel,
    required Color stageColor,
  }) {
    return Material(
      color: palette.surface.withValues(alpha: 0.96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: palette.border),
      ),
      elevation: 3,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: compact ? AppSpacing.xs : AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: palette.textPrimary,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        stageLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MdrrmoTypography.labelSm.copyWith(
                          color: stageColor,
                          fontSize: 10,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        destinationTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MdrrmoTypography.titleMd.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_editingDestination && _destination != null)
                  TextButton(
                    onPressed: () => setState(() => _editingDestination = false),
                    child: const Text('Done'),
                  ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: const LinearProgressIndicator(minHeight: 2.5),
              ),
            ],
            if (needsSearch) ...[
              const SizedBox(height: AppSpacing.xs),
              Container(
                decoration: BoxDecoration(
                  color: palette.surfaceSubtle,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: palette.border),
                ),
                padding: const EdgeInsets.only(left: AppSpacing.sm, right: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        enabled: !_searching,
                        decoration: const InputDecoration(
                          labelText: 'Destination address',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _findDestination(),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Find destination',
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      onPressed: _searching ? null : _findDestination,
                      icon: Icon(AppIcons.search, color: palette.brand),
                    ),
                  ],
                ),
              ),
              if (_searching)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (_searchError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _searchError!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MdrrmoTypography.bodySm.copyWith(
                      color: palette.danger,
                    ),
                  ),
                ),
              if (_matches.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: compact ? 76 : 124),
                  child: Material(
                    color: palette.surfaceSubtle,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      side: BorderSide(color: palette.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _matches.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: palette.border),
                      itemBuilder: (_, index) {
                        final match = _matches[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            AppIcons.pin,
                            size: 16,
                            color: palette.brand,
                          ),
                          title: Text(
                            match.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: _busy ? null : () => _preview(match.point),
                        );
                      },
                    ),
                  ),
                ),
              ],
              if (_pendingPin != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: AppButton(
                    label: 'Confirm destination and route',
                    icon: AppIcons.check,
                    onPress: _busy ? null : _confirmDestination,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHospitalArrivalPrompt({
    required MdrrmoColors palette,
    required HospitalRecommendation hospital,
  }) {
    final busy = _advancingStatus || (widget.responderState?.isSaving ?? false);
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: palette.brand, width: 1.5),
      ),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(AppIcons.hospital, color: palette.brand, size: 22),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Arrived at ${hospital.name}',
                        style: MdrrmoTypography.titleMd.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        'Confirm to complete this dispatch.',
                        style: MdrrmoTypography.bodySm.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            _dismissedHospitalPromptIds.add(hospital.id);
                            _hospitalArrivalPromptId = null;
                          }),
                    child: const Text('Not Yet'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: busy || !hospital.isAvailable
                        ? null
                        : () => _advanceDispatch(
                            expectedStep: 3,
                            skipConfirm: true,
                          ),
                    child: const Text('Arrived'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPanel(
    BuildContext context, {
    required MdrrmoColors palette,
    required Assignment? assignment,
    required String destinationTitle,
    required bool compact,
  }) {
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.lg),
        ),
        side: BorderSide(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          compact ? AppSpacing.sm : AppSpacing.md,
        ),
        child: _buildBottomPanelContent(
          context,
          palette: palette,
          assignment: assignment,
          destinationTitle: destinationTitle,
          compact: compact,
        ),
      ),
    );
  }

  Widget _buildBottomPanelContent(
    BuildContext context, {
    required MdrrmoColors palette,
    required Assignment? assignment,
    required String destinationTitle,
    required bool compact,
  }) {
    final busy = _advancingStatus || (widget.responderState?.isSaving ?? false);
    final totals = _remainingRouteTotals();
    final etaMinutes = _route != null ? (totals.$2 / 60).ceil() : null;
    final distanceKm = _route != null
        ? (totals.$1 / 1000).toStringAsFixed(1)
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isSchedule) ...[
          _buildNavStepper(
            palette: palette,
            labels: const ['Pickup', 'Destination', 'Complete'],
            current: _isSchedulePickupPhase
                ? 0
                : (_scheduleStatus == 'completed' ? 2 : 1),
          ),
          const SizedBox(height: AppSpacing.sm),
        ] else if (assignment != null) ...[
          _buildNavStepper(
            palette: palette,
            labels: const ['En Route', 'On Scene', 'Complete'],
            current: assignment.step.clamp(0, 2),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        // ── ETA & distance summary + panel toggles ──
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_route != null)
                    Wrap(
                      spacing: AppSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '$etaMinutes min',
                          style: MdrrmoTypography.tabular(
                            MdrrmoTypography.titleLg.copyWith(
                              color: palette.brand,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '$distanceKm km',
                          style: MdrrmoTypography.tabular(
                            MdrrmoTypography.bodyMd.copyWith(
                              color: palette.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      _busy ? 'Calculating route…' : destinationTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MdrrmoTypography.titleMd.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                  if (_route != null)
                    Text(
                      destinationTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MdrrmoTypography.bodySm.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (_showHospitalSuggestions)
              Flexible(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => setState(() {
                    _showHospitals = !_showHospitals;
                    if (_showHospitals) _showDirections = false;
                  }),
                  icon: Icon(
                    AppIcons.hospital,
                    size: 16,
                    color: _selectedHospital != null
                        ? palette.brand
                        : palette.textSecondary,
                  ),
                  label: Text(
                    _selectedHospital != null
                        ? 'Hospital'
                        : 'Recommended hospitals',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            if (_route?.directions.isNotEmpty ?? false)
              IconButton(
                tooltip: 'Road directions',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () => setState(() {
                  _showDirections = !_showDirections;
                  if (_showDirections) _showHospitals = false;
                }),
                icon: Icon(
                  _showDirections
                      ? Icons.expand_more_rounded
                      : AppIcons.route,
                  size: 20,
                  color: palette.textSecondary,
                ),
              ),
          ],
        ),

        // ── Relevant dispatch or schedule action for current trip stage ──
        if (_isSchedule) ...[
          const SizedBox(height: AppSpacing.xs),
          _buildScheduleActionRow(
            palette: palette,
            busy: busy,
          ),
        ] else if (assignment != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _buildDispatchActionRow(
            palette: palette,
            assignment: assignment,
            busy: busy,
          ),
        ] else if (_selectedHospital != null && !_showHospitals) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : () => _selectHospital(null),
              child: const Text('Return to incident route'),
            ),
          ),
        ],

        // ── Expandable hospital picker ──
        if (_showHospitals && _showHospitalSuggestions) ...[
          const SizedBox(height: AppSpacing.xs),
          Builder(
            builder: (context) {
              final hospitalList = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_selectedHospital != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _busy ? null : () => _selectHospital(null),
                        child: const Text('Return to incident route'),
                      ),
                    ),
                  if (_loadingHospitals) const LinearProgressIndicator(minHeight: 2),
                  if (_hospitalError != null)
                    TextButton(
                      onPressed: _loadHospitals,
                      child: Text('$_hospitalError Retry'),
                    ),
                  if (!_loadingHospitals &&
                      _hospitalError == null &&
                      _hospitals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'No hospitals on file. Contact the dispatcher.',
                      ),
                    ),
                  for (final hospital in _hospitals)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      selected: _selectedHospital?.id == hospital.id,
                      selectedTileColor: palette.brandTint,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      enabled: !_busy,
                      title: Text(hospital.name),
                      subtitle: Text(
                        '${hospital.distanceKm.toStringAsFixed(1)} km from incident${hospital.specialtyMatch ? ' · Specialty match' : ''}\n${hospital.availableBeds == null ? 'Bed availability unconfirmed' : '${hospital.availableBeds} beds'}${hospital.contact == null ? '' : ' · ${hospital.contact}'}',
                      ),
                      trailing: Icon(
                        _selectedHospital?.id == hospital.id
                            ? AppIcons.check
                            : AppIcons.navigation,
                        size: 18,
                      ),
                      onTap: () => _selectHospital(hospital),
                    ),
                ],
              );
              if (compact) return hospitalList;
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 210),
                child: SingleChildScrollView(child: hospitalList),
              );
            },
          ),
        ],

        // ── Expandable turn-by-turn directions ──
        if (_showDirections && (_route?.directions.isNotEmpty ?? false)) ...[
          const SizedBox(height: AppSpacing.xs),
          Builder(
            builder: (context) {
              Widget stepTile(int i) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 11,
                  backgroundColor: palette.brandTint,
                  child: Text(
                    '${i + 1}',
                    style: MdrrmoTypography.bodySm.copyWith(
                      color: palette.brand,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                title: Text(_route!.directions[i]),
              );
              if (compact) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _route!.directions.length; i++)
                      stepTile(i),
                  ],
                );
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 190),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _route!.directions.length,
                  itemBuilder: (_, i) => stepTile(i),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildNavStepper({
    required MdrrmoColors palette,
    required List<String> labels,
    required int current,
  }) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: i <= current ? palette.brand : palette.border,
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < current
                      ? palette.success
                      : i == current
                      ? palette.brand
                      : palette.surfaceSubtle,
                  border: Border.all(
                    color: i < current
                        ? palette.success
                        : i == current
                        ? palette.brand
                        : palette.border,
                  ),
                ),
                child: i < current
                    ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                    : Text(
                        '${i + 1}',
                        style: MdrrmoTypography.labelSm.copyWith(
                          fontSize: 10,
                          color: i == current ? Colors.white : palette.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              const SizedBox(width: 5),
              Text(
                labels[i],
                style: MdrrmoTypography.labelSm.copyWith(
                  color: i <= current ? palette.textPrimary : palette.textMuted,
                  fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildScheduleActionRow({
    required MdrrmoColors palette,
    required bool busy,
  }) {
    final label = switch (_scheduleStatus) {
      'confirmed' => 'Start trip',
      'en-route' => 'Mark on scene',
      _ => 'Complete service',
    };
    final icon = switch (_scheduleStatus) {
      'confirmed' => AppIcons.navigation,
      'en-route' => AppIcons.user,
      _ => AppIcons.checkCircle,
    };

    return Row(
      children: [
        Expanded(
          child: AppButton(
            label: busy ? 'Saving update...' : label,
            icon: icon,
            loading: busy,
            onPress: busy ? null : _advanceScheduleStatus,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _editingDestination = !_editingDestination;
                  _search.text = _activeAddress;
                }),
          icon: const Icon(AppIcons.pin, size: 16),
          label: const Text('Pin'),
        ),
      ],
    );
  }

  Widget _buildDispatchActionRow({
    required MdrrmoColors palette,
    required Assignment assignment,
    required bool busy,
  }) {
    final step = assignment.step;
    final hasAvailableHospital =
        _selectedHospital != null && _selectedHospital!.isAvailable;

    if (!assignment.hasActionButton) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: palette.surfaceSubtle,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Icon(AppIcons.navigation, size: 16, color: palette.brand),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'En route — On Scene triggers automatically within 5 m of the incident.',
                style: MdrrmoTypography.bodySm.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final label = switch (step) {
      0 => 'Start trip',
      2 => 'Transporting',
      _ => 'Complete dispatch',
    };
    final icon = switch (step) {
      0 => AppIcons.navigation,
      2 => AppIcons.hospital,
      _ => AppIcons.checkCircle,
    };
    final canPress = !busy && (step != 3 || hasAvailableHospital);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: busy ? 'Saving update...' : label,
                icon: icon,
                loading: busy,
                onPress: canPress
                    ? () => _advanceDispatch(expectedStep: step)
                    : null,
              ),
            ),
            if (step == 3 && _selectedHospital != null) ...[
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: busy ? null : _markSelectedHospitalUnavailable,
                icon: const Icon(AppIcons.close, size: 16),
                label: const Text('Not Available'),
              ),
            ] else if (step == 3 &&
                _selectedHospital == null &&
                _hospitals.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _showHospitals = true;
                        _showDirections = false;
                      }),
                icon: const Icon(AppIcons.hospital, size: 16),
                label: const Text('Hospital'),
              ),
            ],
          ],
        ),
        if (step == 3 && !hasAvailableHospital) ...[
          const SizedBox(height: 6),
          Text(
            'No available hospital selected. Select an available hospital to enable Arrived.',
            style: MdrrmoTypography.labelSm.copyWith(color: palette.warning),
          ),
        ],
      ],
    );
  }
}
