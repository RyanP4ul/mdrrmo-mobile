import 'package:material_ui/material_ui.dart';

import 'kit.dart';

class PageLoader extends StatelessWidget {
  const PageLoader({
    super.key,
    required this.hasMore,
    required this.loading,
    required this.onLoad,
    this.error,
  });
  final bool hasMore;
  final bool loading;
  final Future<void> Function() onLoad;
  final Object? error;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.xs,
            ),
            child: AppBanner(
              tone: AppBannerTone.danger,
              message: apiErrorMessage(error!),
            ),
          ),
        if (hasMore || error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: AppButton(
              label: loading
                  ? 'Loading...'
                  : error == null
                  ? 'Load more'
                  : 'Try again',
              kind: AppButtonKind.outline,
              loading: loading,
              onPress: loading ? null : onLoad,
            ),
          ),
      ],
    );
  }
}
