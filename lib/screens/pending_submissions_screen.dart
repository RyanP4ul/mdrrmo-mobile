import 'package:material_ui/material_ui.dart';

import '../data/api_client.dart';
import '../data/resident_models.dart';
import '../services/pending_submissions.dart';
import '../ui/kit.dart';
import '../ui/record_widgets.dart';

class PendingSubmissionsScreen extends StatefulWidget {
  const PendingSubmissionsScreen({super.key, required this.onRecovered});
  final Future<void> Function() onRecovered;

  @override
  State<PendingSubmissionsScreen> createState() =>
      _PendingSubmissionsScreenState();
}

class _PendingSubmissionsScreenState extends State<PendingSubmissionsScreen> {
  List<PendingSubmission> _records = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? errorMessage}) async {
    var nextRecords = _records;
    var nextError = errorMessage;
    try {
      nextRecords = await PendingSubmissions.read();
    } catch (_) {
      nextError ??=
          'Could not read saved submissions. Check secure storage and try again.';
    }
    if (!mounted) return;
    setState(() {
      _records = nextRecords;
      _error = nextError;
      _loading = false;
    });
  }

  Future<void> _retry(PendingSubmission record) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? errorMessage;
    try {
      final confirmed = await PendingSubmissions.send(
        dio,
        record.path,
        record.payload,
        validate: (data) {
          if (record.path.endsWith('/schedules')) {
            ScheduleRequest.fromJson(
              Map<String, dynamic>.from(data['schedule'] as Map),
            );
          } else {
            ReportRecord.fromJson(
              Map<String, dynamic>.from(data['report'] as Map),
            );
          }
          if (data['notification'] is Map) {
            ResidentNotification.fromJson(
              Map<String, dynamic>.from(data['notification'] as Map),
            );
          }
        },
      );
      await widget.onRecovered();
      if (mounted) {
        final ref = confirmed['report'] is Map
            ? confirmed['report']['reference'] ?? ''
            : '';
        snack(
          context,
          'Submission $ref confirmed. Your records have been refreshed.',
        );
      }
    } catch (error) {
      errorMessage = apiErrorMessage(error);
    } finally {
      await _load(errorMessage: errorMessage);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard(PendingSubmission record) async {
    if (_busy) return;
    final confirm = await confirmDialog(
      context,
      title: 'Discard saved submission?',
      body:
          'Only discard if you are sure this request is no longer needed or already appears in your records.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (!confirm || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? errorMessage;
    try {
      await PendingSubmissions.complete(
        record.key,
        storageKey: record.storageKey,
      );
      if (mounted) {
        snack(context, 'Saved submission removed.');
      }
    } catch (error) {
      errorMessage = apiErrorMessage(error);
    } finally {
      await _load(errorMessage: errorMessage);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return AppScaffold(
      header: pushedHeader(context, 'Pending submissions'),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxxl,
              ),
              children: [
                ContentFrame(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AppBanner(
                        tone: AppBannerTone.info,
                        icon: AppIcons.refresh,
                        message:
                            'If a connection failed while sending, confirm the saved submission here before creating another. Retrying confirms the original request without creating a duplicate.',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (_error != null) ...[
                        AppBanner(
                          tone: AppBannerTone.danger,
                          icon: AppIcons.alert,
                          message: _error!,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (_records.isEmpty && _error == null)
                        const AppStateView(
                          icon: AppIcons.checkCircle,
                          title: 'No pending submissions',
                          message: 'All saved requests have been confirmed.',
                        ),
                      if (_error != null && _records.isEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 48),
                            ),
                            onPressed: _busy ? null : _load,
                            icon: const Icon(AppIcons.refresh, size: 17),
                            label: const Text('Try again'),
                          ),
                        ),
                      for (final record in _records)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: Surface(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        record.label,
                                        style: MdrrmoTypography.titleMd
                                            .copyWith(
                                              color: palette.textPrimary,
                                            ),
                                      ),
                                    ),
                                    if (record.createdAt != null)
                                      Text(
                                        recordTimestamp(
                                          record.createdAt!.toIso8601String(),
                                        ),
                                        style: MdrrmoTypography.tabular(
                                          MdrrmoTypography.labelSm.copyWith(
                                            color: palette.textMuted,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                if (record.location.isNotEmpty) ...[
                                  const SizedBox(height: AppSpacing.xs),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        AppIcons.pin,
                                        size: 16,
                                        color: palette.brand,
                                      ),
                                      const SizedBox(width: AppSpacing.xs),
                                      Expanded(
                                        child: Text(
                                          record.location,
                                          style: MdrrmoTypography.bodySm
                                              .copyWith(
                                                color: palette.textPrimary,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (record.summary != null) ...[
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    record.summary!,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: MdrrmoTypography.bodySm.copyWith(
                                      color: palette.textSecondary,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: AppSpacing.md),
                                AppButton(
                                  label: _busy
                                      ? 'Confirming...'
                                      : 'Confirm submission',
                                  loading: _busy,
                                  onPress: _busy ? null : () => _retry(record),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                AppButton(
                                  label: 'Discard queued request',
                                  icon: AppIcons.trash,
                                  kind: AppButtonKind.dangerOutline,
                                  onPress: _busy
                                      ? null
                                      : () => _discard(record),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
