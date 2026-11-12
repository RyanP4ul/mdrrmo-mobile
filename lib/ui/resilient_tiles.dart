import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:material_ui/material_ui.dart';

import 'kit.dart';

/// Keeps map interactions available when the external tile service fails.
class ResilientTiles extends StatefulWidget {
  const ResilientTiles({super.key});
  @override
  State<ResilientTiles> createState() => _ResilientTilesState();
}

class _ResilientTilesState extends State<ResilientTiles> {
  final _reset = StreamController<void>.broadcast();
  bool _failed = false;
  bool _pending = false;
  @override
  void dispose() {
    _reset.close();
    super.dispose();
  }

  void _failedTile() {
    if (_failed || _pending) return;
    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _pending = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'ph.gov.mdrrmo.responder',
          reset: _reset.stream,
          errorTileCallback: (_, _, _) => _failedTile(),
        ),
        if (_failed)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Material(
                color: palette.surface.withValues(alpha: 0.96),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  side: BorderSide(color: palette.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        AppIcons.alert,
                        size: 16,
                        color: palette.warningIcon,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          'Map tiles unavailable. Your pin is preserved.',
                          style: MdrrmoTypography.labelSm.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() => _failed = false);
                          _reset.add(null);
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
