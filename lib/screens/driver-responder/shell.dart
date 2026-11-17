import 'dart:async';

import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../services/driver_realtime.dart';
import '../../services/driver_tracking.dart';
import '../../state/driver_responder_state.dart';
import '../../ui/kit.dart';
import '../../ui/logout_action.dart';
import '../responder_records_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'service_schedules_screen.dart';
import 'team_screen.dart';

class Shell extends StatefulWidget {
  const Shell({
    super.key,
    required this.tracking,
    required this.realtime,
    required this.onLocationAccessChanged,
  });

  final ValueChanged<bool> onLocationAccessChanged;
  final DriverTracking tracking;
  final DriverRealtime realtime;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  int _lastDispatchTabRequest = 0;
  StreamSubscription<Map<String, dynamic>>? _reportSub;

  @override
  void initState() {
    super.initState();
    _reportSub = widget.realtime.reportEvents.listen(_onReportUpdated);
  }

  @override
  void dispose() {
    unawaited(_reportSub?.cancel());
    super.dispose();
  }

  void _onReportUpdated(Map<String, dynamic> data) {
    if (!mounted || data['status'] != 'dispatched') return;
    unawaited(HapticFeedback.heavyImpact());
    final type = data['incident_type']?.toString().trim();
    final ref = data['reference']?.toString().trim();
    final location = data['location']?.toString().trim();
    final title = [
      'New dispatch',
      if (type != null && type.isNotEmpty) type,
      if (ref != null && ref.isNotEmpty) '($ref)',
    ].join(' ');
    final message = location != null && location.isNotEmpty ? '$title — $location' : title;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        action: _index != 0
            ? SnackBarAction(
                label: 'View',
                onPressed: () {
                  if (mounted) setState(() => _index = 0);
                },
              )
            : null,
      ),
    );
  }

  Future<void> _menu(ResponderState state) async {
    final choice = await showAppSheet<int>(
      context,
      title: 'More options',
      subtitle: 'Sync and session',
      builder: (sheetCtx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSectionGroup(
              children: [
                AppRowItem(
                  title: 'Refresh information',
                  subtitle: 'Reload latest assignments now',
                  showChevron: true,
                  onTap: () => Navigator.pop(sheetCtx, 0),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppSectionGroup(
              children: [
                AppRowItem(
                  destructive: true,
                  title: 'Log out',
                  subtitle: 'Sign out of this device',
                  onTap: () => Navigator.pop(sheetCtx, 1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 0) {
      await state.load();
    } else if (choice == 1) {
      await logoutFrom(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ResponderScope.of(context);
    if (state.dispatchTabRequests != _lastDispatchTabRequest) {
      _lastDispatchTabRequest = state.dispatchTabRequests;
      _index = 0;
    }
    final palette = MdrrmoColors.of(context);
    final statusColor = !state.hasLoaded
        ? palette.textMuted
        : switch (state.availability) {
            Availability.available => palette.success,
            Availability.dispatched => palette.brand,
            Availability.offDuty => palette.textMuted,
          };
    final activeAssignmentsCount = state.assignments.length;
    final scaledFont = MediaQuery.textScalerOf(context).scale(12);
    final navHeight = scaledFont > 16 ? 78.0 : 66.0;

    return AppScaffold(
      childPad: false,
      header: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(bottom: BorderSide(color: palette.border)),
        ),
        child: FHeader(
          style: .delta(
            systemOverlayStyle: palette.isDark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LogoMark(size: 30),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Balagtas MDRRMO',
                      overflow: TextOverflow.ellipsis,
                      style: MdrrmoTypography.titleMd.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            state.isDriver ? 'Driver & Responder' : 'Responder',
                            overflow: TextOverflow.ellipsis,
                            style: MdrrmoTypography.labelSm.copyWith(
                              color: palette.textSecondary,
                              fontWeight: FontWeight.w600,
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
          suffixes: [
            FHeaderAction(
              icon: Badge(
                isLabelVisible: state.unreadCount > 0,
                backgroundColor: palette.danger,
                textColor: palette.brandOn,
                label: Text(
                  state.unreadCount > 99 ? '99+' : '${state.unreadCount}',
                ),
                child: Icon(
                  AppIcons.bell,
                  color: palette.textPrimary,
                  semanticLabel: 'Notifications',
                ),
              ),
              onPress: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ResponderRecordsScreen(
                    inbox: true,
                    onChanged: state.load,
                  ),
                ),
              ),
            ),
            FHeaderAction(
              icon: Icon(
                AppIcons.more,
                color: palette.textPrimary,
                semanticLabel: 'More options',
              ),
              onPress: () => _menu(state),
            ),
          ],
        ),
      ),
      footer: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(top: BorderSide(color: palette.border)),
          boxShadow: palette.isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            height: navHeight,
            elevation: 0,
            backgroundColor: palette.surface,
            surfaceTintColor: Colors.transparent,
            indicatorColor: palette.brandTint,
            indicatorShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return MdrrmoTypography.labelSm.copyWith(
                color: selected ? palette.brand : palette.textMuted,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (index) {
              if (_index == index) return;
              unawaited(HapticFeedback.selectionClick());
              setState(() => _index = index);
            },
            labelPadding: EdgeInsets.zero,
            destinations: [
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: activeAssignmentsCount > 0,
                  backgroundColor: palette.brand,
                  textColor: palette.brandOn,
                  label: Text(
                    activeAssignmentsCount > 9
                        ? '9+'
                        : '$activeAssignmentsCount',
                  ),
                  child: Icon(AppIcons.ambulance, color: palette.textMuted),
                ),
                selectedIcon: Badge(
                  isLabelVisible: activeAssignmentsCount > 0,
                  backgroundColor: palette.brand,
                  textColor: palette.brandOn,
                  label: Text(
                    activeAssignmentsCount > 9
                        ? '9+'
                        : '$activeAssignmentsCount',
                  ),
                  child: Icon(AppIcons.ambulance, color: palette.brand),
                ),
                label: 'Dispatch',
              ),
              NavigationDestination(
                icon: Icon(AppIcons.stethoscope, color: palette.textMuted),
                selectedIcon: Icon(AppIcons.stethoscope, color: palette.brand),
                label: 'Service',
              ),
              NavigationDestination(
                icon: Icon(AppIcons.users, color: palette.textMuted),
                selectedIcon: Icon(AppIcons.users, color: palette.brand),
                label: 'Team',
              ),
              NavigationDestination(
                icon: Icon(AppIcons.history, color: palette.textMuted),
                selectedIcon: Icon(AppIcons.history, color: palette.brand),
                label: 'History',
              ),
            ],
          ),
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                TickerMode(
                  enabled: _index == 0,
                  child: HomeScreen(
                    realtime: widget.realtime,
                    tracking: widget.tracking,
                  ),
                ),
                TickerMode(
                  enabled: _index == 1,
                  child: ServiceSchedulesScreen(api: state.api),
                ),
                TickerMode(
                  enabled: _index == 2,
                  child: const ResponderTeamScreen(),
                ),
                TickerMode(enabled: _index == 3, child: const HistoryScreen()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
