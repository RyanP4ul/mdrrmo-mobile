import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';

import '../data/api_client.dart';
import '../data/paged_records.dart';
import '../ui/kit.dart';

/// Embeddable searchable/filterable paged record browser.
class RecordBrowserView extends StatefulWidget {
  const RecordBrowserView({
    super.key,
    required this.path,
    required this.label,
    this.subtitle,
    this.onOpen,
    this.onCreate,
    this.filters = const {},
    this.fixed = const {},
    this.pick = false,
    this.client,
  });

  final String path;
  final String Function(Map<String, dynamic>) label;
  final String Function(Map<String, dynamic>)? subtitle;
  final Future<void> Function(BuildContext, Map<String, dynamic>)? onOpen;
  final Future<void> Function(BuildContext)? onCreate;
  final Map<String, Map<String, String>> filters;
  final Map<String, dynamic> fixed;
  final bool pick;
  final Dio? client;

  @override
  State<RecordBrowserView> createState() => _RecordBrowserViewState();
}

class _RecordBrowserViewState extends State<RecordBrowserView> {
  final _search = TextEditingController();
  final _selected = <String, String>{};
  CancelToken? _cancel;
  List<Map<String, dynamic>> _items = [];
  DateTime? _from, _to;
  int? _next;
  bool _busy = false;
  Object? _error;

  Dio get _api => widget.client ?? dio;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RecordBrowserView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _cancel?.cancel();
      _selected.clear();
      _items = [];
      _next = null;
      _error = null;
      _load();
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _search.dispose();
    super.dispose();
  }

  String _date(DateTime day) => day.toIso8601String().substring(0, 10);

  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    if (_from != null && _to != null && _to!.isBefore(_from!)) {
      snack(context, 'The end date must follow the start date.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    _cancel = CancelToken();
    try {
      final response = await _api.get(
        widget.path,
        queryParameters: {
          ...widget.fixed,
          ..._selected,
          if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
          if (_from != null) 'from': _date(_from!),
          if (_to != null) 'to': _date(_to!),
          if (more && _next != null) 'before': _next,
        },
        cancelToken: _cancel,
      );
      final page = RecordPage.fromJson(response.data);
      if (mounted) {
        setState(() {
          _items = more
              ? mergeRecords(_items, page.items, (item) => item['id'] as Object)
              : page.items;
          _next = page.nextBefore;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseDate(bool from) async {
    final date = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      setState(() {
        if (from) {
          _from = date;
        } else {
          _to = date;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ContentFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Surface(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _search,
                        enabled: !_busy,
                        onSubmitted: (_) => _load(),
                        decoration: const InputDecoration(
                          labelText: 'Search all records',
                          prefixIcon: Icon(AppIcons.search, size: 18),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          TextButton(
                            onPressed: _busy ? null : () => _chooseDate(true),
                            child: Text(
                              'From: ${_from == null ? 'Any' : _date(_from!)}',
                            ),
                          ),
                          TextButton(
                            onPressed: _busy ? null : () => _chooseDate(false),
                            child: Text(
                              'To: ${_to == null ? 'Any' : _date(_to!)}',
                            ),
                          ),
                        ],
                      ),
                      for (final f in widget.filters.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('${f.key}:${_selected[f.key]}'),
                            initialValue: _selected[f.key] ?? '',
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: f.key.replaceAll('_', ' '),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('All'),
                              ),
                              for (final option in f.value.entries)
                                DropdownMenuItem(
                                  value: option.key,
                                  child: Text(option.value),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => setState(() {
                                    if (value == null || value.isEmpty) {
                                      _selected.remove(f.key);
                                    } else {
                                      _selected[f.key] = value;
                                    }
                                  }),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Expanded(
                            child: AppButton(
                              label: 'Apply filters',
                              onPress: _busy ? null : () => _load(),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    setState(() {
                                      _search.clear();
                                      _selected.clear();
                                      _from = null;
                                      _to = null;
                                    });
                                    _load();
                                  },
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (widget.onCreate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                await widget.onCreate!(context);
                                if (mounted) await _load();
                              },
                        icon: const Icon(AppIcons.plus, size: 18),
                        label: const Text('Create new'),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.md),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_error != null) ...[
                  AppBanner(
                    tone: AppBannerTone.danger,
                    icon: AppIcons.alert,
                    message: apiErrorMessage(_error!),
                    action: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _busy
                            ? null
                            : () => _load(
                                more: _items.isNotEmpty && _next != null,
                              ),
                        child: const Text('Retry'),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (!_busy && _error == null && _items.isEmpty)
                  const AppStateView(
                    icon: AppIcons.inbox,
                    title: 'No matching records',
                    message: 'No records match these filters.',
                  ),
                for (final record in _items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
                    child: Surface(
                      padding: EdgeInsets.zero,
                      child: AppRowItem(
                        padding: const EdgeInsets.all(AppSpacing.md + 2),
                        showChevron: widget.pick || widget.onOpen != null,
                        title: widget.label(record),
                        subtitle: widget.subtitle?.call(record),
                        trailing: (widget.pick || widget.onOpen != null)
                            ? Icon(
                                AppIcons.chevron,
                                size: 18,
                                color: palette.textMuted,
                              )
                            : null,
                        onTap: widget.pick
                            ? () => Navigator.pop(context, record)
                            : widget.onOpen == null
                            ? null
                            : () async {
                                await widget.onOpen!(context, record);
                                if (mounted) await _load();
                              },
                      ),
                    ),
                  ),
                if (_next != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: TextButton(
                      onPressed: _busy ? null : () => _load(more: true),
                      child: const Text('Load older matching records'),
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

/// Search is applied to the complete authorized server collection, not loaded cards.
class RecordBrowserScreen extends StatelessWidget {
  const RecordBrowserScreen({
    super.key,
    required this.title,
    required this.path,
    required this.label,
    this.subtitle,
    this.onOpen,
    this.onCreate,
    this.filters = const {},
    this.fixed = const {},
    this.pick = false,
    this.client,
  });

  final String title, path;
  final String Function(Map<String, dynamic>) label;
  final String Function(Map<String, dynamic>)? subtitle;
  final Future<void> Function(BuildContext, Map<String, dynamic>)? onOpen;
  final Future<void> Function(BuildContext)? onCreate;
  final Map<String, Map<String, String>> filters;
  final Map<String, dynamic> fixed;
  final bool pick;
  final Dio? client;

  @override
  Widget build(BuildContext context) => AppScaffold(
    header: pushedHeader(context, title),
    childPad: false,
    child: RecordBrowserView(
      path: path,
      label: label,
      subtitle: subtitle,
      onOpen: onOpen,
      onCreate: onCreate,
      filters: filters,
      fixed: fixed,
      pick: pick,
      client: client,
    ),
  );
}

Future<Map<String, dynamic>?> pickRecord(
  BuildContext context, {
  required String title,
  required String path,
  required String Function(Map<String, dynamic>) label,
}) => Navigator.of(context).push<Map<String, dynamic>>(
  MaterialPageRoute(
    builder: (_) =>
        RecordBrowserScreen(title: title, path: path, label: label, pick: true),
  ),
);
