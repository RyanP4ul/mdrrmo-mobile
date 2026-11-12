import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../data/api/driver_service.api.dart';
import '../data/hospital.dart';
import '../services/incident_location.dart';
import '../services/road_routing.dart';
import '../ui/kit.dart';
import '../ui/resilient_tiles.dart';

class RouteNavigationScreen extends StatefulWidget {
  const RouteNavigationScreen({
    super.key,
    required this.address,
    this.destination,
    this.routing,
    this.location,
    this.reportId,
    this.hospitalApi,
  });

  final String address;
  final LatLng? destination;
  final RoadRouting? routing;
  final IncidentLocationSource? location;
  final int? reportId;
  final DriverApi? hospitalApi;

  @override
  State<RouteNavigationScreen> createState() => _RouteNavigationScreenState();
}

class _RouteNavigationScreenState extends State<RouteNavigationScreen>
    with WidgetsBindingObserver {
  final _map = MapController();
  final _cancel = CancelToken();
  late final RoadRouting _routing = widget.routing ?? RoadRouting();
  late final IncidentLocationSource _location =
      widget.location ?? DeviceIncidentLocation();
  late final TextEditingController _search = TextEditingController(
    text: widget.address,
  );
  Timer? _timer;
  LatLng? _origin, _destination, _routeOrigin, _pendingPin;
  RoadRoute? _route;
  List<RouteDestination> _matches = [];
  bool _busy = false,
      _ready = false,
      _foreground = true,
      _searching = false,
      _compactViewport = false;
  String? _error, _searchError;
  late final DriverApi _hospitalApi = widget.hospitalApi ?? DriverApi();
  List<HospitalRecommendation> _hospitals = [];
  bool _loadingHospitals = false;
  String? _hospitalError;
  HospitalRecommendation? _selectedHospital;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _destination = widget.destination;
    _refresh();
    if (widget.reportId != null) unawaited(_loadHospitals());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_foreground) unawaited(_refresh(automatic: true));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _cancel.cancel();
    if (widget.routing == null) _routing.dispose();
    if (widget.reportId != null && widget.hospitalApi == null) {
      _hospitalApi.dispose();
    }
    _search.dispose();
    _map.dispose();
    super.dispose();
  }

  void _fit() {
    if (!_ready) return;
    final points = [
      ?_origin,
      ?_destination,
      ...?_route?.points,
      if (_selectedHospital == null)
        ..._hospitals.map((hospital) => hospital.point),
    ];
    if (points.isEmpty) return;
    final needsSearch =
        widget.destination == null && _selectedHospital == null;
    final topPad = _compactViewport
        ? (needsSearch ? 110.0 : 68.0)
        : (needsSearch ? 156.0 : 88.0);
    final bottomPad = _compactViewport ? 140.0 : 196.0;
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: EdgeInsets.fromLTRB(36, topPad, 36, bottomPad),
        maxZoom: 17,
      ),
    );
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
      final origin = await _location.current();
      if (!mounted) return;
      setState(() => _origin = origin);
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
        });
      }
      if (!automatic) _fit();
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
    });
    if (_ready) _map.move(point, 16);
  }

  Future<void> _confirmDestination() async {
    if (_pendingPin == null || _busy) return;
    setState(() {
      _destination = _pendingPin;
      _pendingPin = null;
      _route = null;
    });
    await _refresh();
  }

  Widget _mapMarkerBadge({
    required Color fill,
    required Color iconColor,
    required IconData icon,
    double diameter = 34,
    double iconSize = 18,
    Color borderColor = Colors.white,
    bool highlighted = false,
  }) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor,
          width: highlighted ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: highlighted ? 0.28 : 0.18),
            blurRadius: highlighted ? 10 : 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: iconColor, size: iconSize),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final destinationTitle =
        _selectedHospital?.name ??
        (widget.address.isEmpty ? 'Assigned destination' : widget.address);
    final needsSearch =
        widget.destination == null && _selectedHospital == null;
    final statusLabel = _selectedHospital != null
        ? 'Selected hospital route'
        : needsSearch
        ? (_pendingPin != null ? 'Confirm pin to route' : 'Set trip destination')
        : 'Assigned destination';

    return AppScaffold(
      header: pushedHeader(context, 'Route navigation'),
      childPad: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 480;
          _compactViewport = compact;
          return Stack(
            children: [
              // ── Full-bleed map ──
              Positioned.fill(
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter:
                        widget.destination ?? const LatLng(14.82, 120.90),
                    initialZoom: 14,
                    onMapReady: () {
                      _ready = true;
                      _fit();
                    },
                    onLongPress: needsSearch
                        ? (_, point) => _preview(point)
                        : null,
                  ),
                  children: [
                    const ResilientTiles(),
                    if (_route != null)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _route!.points,
                            strokeWidth: 6,
                            color: palette.brand,
                            borderStrokeWidth: 2.5,
                            borderColor: Colors.white,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        for (final hospital in _hospitals)
                          Marker(
                            point: hospital.point,
                            width: 48,
                            height: 48,
                            child: IconButton(
                              tooltip: hospital.name,
                              padding: EdgeInsets.zero,
                              onPressed: _busy
                                  ? null
                                  : () => _selectHospital(hospital),
                              icon: _mapMarkerBadge(
                                fill: _selectedHospital?.id == hospital.id
                                    ? palette.brand
                                    : palette.surface,
                                iconColor: _selectedHospital?.id == hospital.id
                                    ? Colors.white
                                    : palette.brand,
                                borderColor: _selectedHospital?.id == hospital.id
                                    ? Colors.white
                                    : palette.brand,
                                icon: AppIcons.hospital,
                                diameter:
                                    _selectedHospital?.id == hospital.id ? 38 : 34,
                                highlighted:
                                    _selectedHospital?.id == hospital.id,
                              ),
                            ),
                          ),
                        if (_origin != null)
                          Marker(
                            point: _origin!,
                            width: 40,
                            height: 40,
                            child: Tooltip(
                              message: 'Your current location',
                              child: Center(
                                child: _mapMarkerBadge(
                                  fill: palette.brand,
                                  iconColor: Colors.white,
                                  icon: AppIcons.locate,
                                  diameter: 34,
                                  iconSize: 18,
                                  highlighted: true,
                                ),
                              ),
                            ),
                          ),
                        if (_destination != null)
                          Marker(
                            point: _destination!,
                            width: 44,
                            height: 44,
                            child: Tooltip(
                              message: 'Destination',
                              child: Center(
                                child: _mapMarkerBadge(
                                  fill: palette.danger,
                                  iconColor: Colors.white,
                                  icon: AppIcons.pin,
                                  diameter: 38,
                                  iconSize: 20,
                                  highlighted: true,
                                ),
                              ),
                            ),
                          ),
                        if (_pendingPin != null)
                          Marker(
                            point: _pendingPin!,
                            width: 44,
                            height: 44,
                            child: Tooltip(
                              message: 'Confirm this destination',
                              child: Center(
                                child: _mapMarkerBadge(
                                  fill: palette.warningIcon,
                                  iconColor: Colors.white,
                                  icon: AppIcons.pin,
                                  diameter: 38,
                                  iconSize: 20,
                                  highlighted: true,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const RichAttributionWidget(
                      alignment: AttributionAlignment.bottomLeft,
                      attributions: [
                        TextSourceAttribution('OpenStreetMap contributors'),
                        TextSourceAttribution('Routing: OSRM'),
                        TextSourceAttribution('Address search: Photon'),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Top floating card: destination & address finder ──
              Positioned(
                top: compact ? AppSpacing.sm : AppSpacing.md,
                left: AppSpacing.md,
                right: AppSpacing.md,
                child: SafeArea(
                  bottom: false,
                  child: ContentFrame(
                    child: Material(
                      color: palette.surface.withValues(alpha: 0.96),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        side: BorderSide(color: palette.border),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? AppSpacing.sm : AppSpacing.md,
                          vertical: compact ? AppSpacing.xs : AppSpacing.sm,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: _selectedHospital != null
                                        ? palette.brandTint
                                        : palette.dangerTint,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.md,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    _selectedHospital != null
                                        ? AppIcons.hospital
                                        : AppIcons.pin,
                                    size: 18,
                                    color: _selectedHospital != null
                                        ? palette.brand
                                        : palette.danger,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        statusLabel,
                                        style: MdrrmoTypography.bodySm.copyWith(
                                          color: palette.textSecondary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        destinationTitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: MdrrmoTypography.bodyMd.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: palette.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (_busy) ...[
                              const SizedBox(height: AppSpacing.xs),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                                child: const LinearProgressIndicator(
                                  minHeight: 2.5,
                                ),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: AppSpacing.xs,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.dangerTint,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.sm,
                                  ),
                                  border: Border.all(
                                    color: palette.danger.withValues(
                                      alpha: 0.25,
                                    ),
                                  ),
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
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: MdrrmoTypography.bodySm.copyWith(
                                          color: palette.danger,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (needsSearch) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Container(
                                decoration: BoxDecoration(
                                  color: palette.surfaceSubtle,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                  border: Border.all(color: palette.border),
                                ),
                                padding: const EdgeInsets.only(
                                  left: AppSpacing.sm,
                                  right: 4,
                                ),
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
                                          contentPadding: EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
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
                                      onPressed: _searching
                                          ? null
                                          : _findDestination,
                                      icon: Icon(
                                        AppIcons.search,
                                        color: palette.brand,
                                      ),
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
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: MdrrmoTypography.bodySm.copyWith(
                                      color: palette.danger,
                                    ),
                                  ),
                                ),
                              if (_matches.isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.xs),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: compact ? 76 : 124,
                                  ),
                                  child: Material(
                                    color: palette.surfaceSubtle,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.md,
                                      ),
                                      side: BorderSide(color: palette.border),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      padding: EdgeInsets.zero,
                                      itemCount: _matches.length,
                                      separatorBuilder: (_, _) => Divider(
                                        height: 1,
                                        color: palette.border,
                                      ),
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
                                          onTap: _busy
                                              ? null
                                              : () => _preview(match.point),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                              if (_pendingPin != null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: AppSpacing.xs,
                                  ),
                                  child: AppButton(
                                    label: 'Confirm destination and route',
                                    icon: AppIcons.check,
                                    onPress: _busy ? null : _confirmDestination,
                                  ),
                                )
                              else if (_destination == null &&
                                  _matches.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    'Search the address or long-press the map, then confirm the destination pin.',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: MdrrmoTypography.bodySm.copyWith(
                                      color: palette.textSecondary,
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Bottom draggable sheet: ETA, route actions, hospitals & directions ──
              DraggableScrollableSheet(
                initialChildSize: compact ? 0.36 : 0.30,
                minChildSize: compact ? 0.22 : 0.16,
                maxChildSize: 0.78,
                builder: (sheetCtx, scrollController) => ContentFrame(
                  child: Material(
                    color: palette.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppRadius.lg),
                      ),
                      side: BorderSide(color: palette.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.xl,
                      ),
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: palette.borderStrong,
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                            ),
                          ),
                        ),
                        if (_route != null) ...[
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: palette.brandTint,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  AppIcons.navigation,
                                  size: 20,
                                  color: palette.brand,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${(_route!.distance / 1000).toStringAsFixed(1)} km - ${(_route!.duration / 60).ceil()} min estimated',
                                      style: MdrrmoTypography.tabular(
                                        MdrrmoTypography.titleLg.copyWith(
                                          color: palette.textPrimary,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'Driving route active',
                                      style: MdrrmoTypography.bodySm.copyWith(
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ] else ...[
                          Text(
                            _busy
                                ? 'Calculating driving route…'
                                : 'Route controls',
                            style: MdrrmoTypography.titleMd.copyWith(
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _busy ? null : () => _refresh(),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                ),
                              ),
                              icon: const Icon(AppIcons.refresh, size: 16),
                              label: const Text('Update route'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _fit,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                ),
                              ),
                              icon: const Icon(AppIcons.locate, size: 16),
                              label: const Text('Show route'),
                            ),
                          ],
                        ),
                        if (widget.reportId != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Material(
                            color: palette.surfaceSubtle,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              side: BorderSide(color: palette.border),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ExpansionTile(
                              shape: const Border(),
                              collapsedShape: const Border(),
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: 2,
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                AppSpacing.md,
                                0,
                                AppSpacing.md,
                                AppSpacing.sm,
                              ),
                              leading: Icon(
                                AppIcons.hospital,
                                color: palette.brand,
                                size: 20,
                              ),
                              title: const Text('Recommended hospitals'),
                              subtitle: Text(
                                _selectedHospital?.name ??
                                    'Choose a hospital destination',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              children: [
                                if (_selectedHospital != null)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _selectHospital(null),
                                      child: const Text(
                                        'Return to incident route',
                                      ),
                                    ),
                                  ),
                                if (_loadingHospitals)
                                  const LinearProgressIndicator(minHeight: 2),
                                if (_hospitalError != null)
                                  TextButton(
                                    onPressed: _loadHospitals,
                                    child: Text('$_hospitalError Retry'),
                                  ),
                                if (!_loadingHospitals &&
                                    _hospitalError == null &&
                                    _hospitals.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text(
                                      'No hospitals on file. Contact the dispatcher.',
                                    ),
                                  ),
                                for (final hospital in _hospitals)
                                  ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.xs,
                                    ),
                                    selected:
                                        _selectedHospital?.id == hospital.id,
                                    selectedTileColor: palette.brandTint,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.sm,
                                      ),
                                    ),
                                    enabled: !_busy,
                                    title: Text(hospital.name),
                                    subtitle: Text(
                                      '${hospital.distanceKm.toStringAsFixed(1)} km from incident (straight-line)${hospital.specialtyMatch ? ' · Specialty match' : ''}\n${hospital.availableBeds == null ? 'Bed availability unconfirmed' : '${hospital.availableBeds} beds'}${hospital.contact == null ? '' : ' · ${hospital.contact}'}',
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
                            ),
                          ),
                        ],
                        if (_route?.directions.isNotEmpty ?? false) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Material(
                            color: palette.surfaceSubtle,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              side: BorderSide(color: palette.border),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ExpansionTile(
                              shape: const Border(),
                              collapsedShape: const Border(),
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: 2,
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                AppSpacing.md,
                                0,
                                AppSpacing.md,
                                AppSpacing.sm,
                              ),
                              leading: Icon(
                                AppIcons.route,
                                color: palette.brand,
                                size: 20,
                              ),
                              title: const Text('Road directions'),
                              subtitle: Text(
                                '${_route!.directions.length} turn-by-turn steps',
                              ),
                              children: [
                                for (var i = 0;
                                    i < _route!.directions.length;
                                    i++)
                                  ListTile(
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
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
