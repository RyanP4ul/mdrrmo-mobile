import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/api_client.dart';
import '../ui/data_refresh.dart';
import '../ui/kit.dart';
import '../ui/resilient_tiles.dart';

class FleetMapScreen extends StatefulWidget {
  const FleetMapScreen({super.key});
  @override
  State<FleetMapScreen> createState() => _FleetMapScreenState();
}

class _FleetMapScreenState extends State<FleetMapScreen> {
  final _map = MapController();
  final _cancel = CancelToken();
  List<Map<String, dynamic>> _drivers = [];
  bool _busy = false;
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancel.cancel();
    _map.dispose();
    super.dispose();
  }

  double? _number(Object? value) => double.tryParse('$value');

  List<LatLng> get _points => [
    for (final v in _drivers)
      if (_number(v['lat']) != null && _number(v['lng']) != null)
        LatLng(_number(v['lat'])!, _number(v['lng'])!),
  ];

  void _fit() {
    if (!_ready || _points.isEmpty) return;
    if (_points.length == 1) {
      _map.move(_points.first, 15);
    } else {
      _map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(_points),
          padding: const EdgeInsets.all(40),
          maxZoom: 16,
        ),
      );
    }
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await dio.get(
        '/operations/locations',
        cancelToken: _cancel,
      );
      final result = (response.data['data'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (mounted) {
        setState(() => _drivers = result);
        _fit();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return DataRefresh(
      onRefresh: _load,
      child: AppScaffold(
        header: pushedHeader(context, 'Driver / Responder locations'),
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  0,
                ),
                child: AppBanner(
                  tone: AppBannerTone.danger,
                  icon: AppIcons.wifiOff,
                  message: apiErrorMessage(_error!),
                ),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: AppBanner(
                tone: AppBannerTone.info,
                icon: AppIcons.locate,
                message:
                    'Last known driver/responder locations. Updated every 30 seconds while this screen is open. Older readings are marked stale.',
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: palette.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: const LatLng(14.82, 120.90),
                      initialZoom: 13,
                      onMapReady: () {
                        _ready = true;
                        _fit();
                      },
                    ),
                    children: [
                      const ResilientTiles(),
                      MarkerLayer(
                        markers: [
                          for (final v in _drivers)
                            if (_number(v['lat']) != null &&
                                _number(v['lng']) != null)
                              Marker(
                                point: LatLng(
                                  _number(v['lat'])!,
                                  _number(v['lng'])!,
                                ),
                                width: 96,
                                height: 64,
                                child: GestureDetector(
                                  onTap: () => snack(
                                    context,
                                    '${v['name']}: ${v['status']}. Last reading ${v['updatedAt'] ?? 'Unknown'}',
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        AppIcons.pin,
                                        size: 28,
                                        color: _fresh(v)
                                            ? palette.success
                                            : palette.warning,
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: palette.surface.withValues(
                                            alpha: 0.94,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            AppRadius.xs,
                                          ),
                                          border: Border.all(
                                            color: palette.border,
                                          ),
                                        ),
                                        child: Text(
                                          '${v['name']}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: MdrrmoTypography.labelSm
                                              .copyWith(
                                                color: palette.textPrimary,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                        ],
                      ),
                      const RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution('OpenStreetMap contributors'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_points.isEmpty && !_busy)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  0,
                ),
                child: Text(
                  'No driver/responder locations recorded yet.',
                  style: MdrrmoTypography.bodySm.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
                onPressed: _busy ? null : _load,
                icon: const Icon(AppIcons.refresh, size: 18),
                label: const Text('Refresh locations'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _fresh(Map<String, dynamic> v) {
    final time = DateTime.tryParse('${v['updatedAt']}');
    return time != null &&
        DateTime.now().difference(time) < const Duration(minutes: 3);
  }
}
