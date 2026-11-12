import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../services/driver_realtime.dart';
import '../../services/driver_tracking.dart';
import '../../state/driver_responder_state.dart';
import '../../ui/kit.dart';
import '../../ui/logout_action.dart';
import '../account_screen.dart';
import '../location_access_gate.dart';
import '../pending_submissions_screen.dart';
import '../responder_records_screen.dart';
import '../search_screen.dart';
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

  Widget _leadingIcon(IconData icon, Color tint) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: tint.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Icon(icon, size: 18, color: tint),
  );

  Future<void> _menu(ResponderState state) async {
    final palette = MdrrmoColors.of(context);
    final accountSubtitle = state.profile.name.isNotEmpty
        ? state.profile.name
        : 'Profile, contact details, and password';
    final choice = await showAppSheet<int>(
      context,
      title: 'More options',
      subtitle: 'Account, records, and sync',
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
                  leading: _leadingIcon(AppIcons.user, palette.brand),
                  title: 'Account & profile',
                  subtitle: accountSubtitle,
                  showChevron: true,
                  onTap: () => Navigator.pop(sheetCtx, 0),
                ),
                AppRowItem(
                  leading: _leadingIcon(AppIcons.form, palette.brand),
                  title: 'Reports I submitted',
                  subtitle: 'Driver, emergency, and maintenance entries',
                  showChevron: true,
                  onTap: () => Navigator.pop(sheetCtx, 1),
                ),
                AppRowItem(
                  leading: _leadingIcon(AppIcons.upload, palette.brand),
                  title: 'Unconfirmed submissions',
                  subtitle: 'Retry queued reports or inspect details',
                  showChevron: true,
                  onTap: () => Navigator.pop(sheetCtx, 2),
                ),
                AppRowItem(
                  leading: _leadingIcon(AppIcons.search, palette.brand),
                  title: 'Search records',
                  subtitle: 'Find dispatches and logs',
                  showChevron: true,
                  onTap: () => Navigator.pop(sheetCtx, 4),
                ),
                AppRowItem(
                  leading: _leadingIcon(AppIcons.refresh, palette.brand),
                  title: 'Refresh information',
                  subtitle: 'Reload latest assignments now',
                  showChevron: true,
                  onTap: () => Navigator.pop(sheetCtx, 5),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppSectionGroup(
              children: [
                AppRowItem(
                  leading: _leadingIcon(AppIcons.logout, palette.danger),
                  destructive: true,
                  title: 'Log out',
                  subtitle: 'Sign out of this device',
                  onTap: () => Navigator.pop(sheetCtx, 6),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 5) {
      await state.load();
      return;
    }
    if (choice == 6) {
      await logoutFrom(context);
      return;
    }
    final page = switch (choice) {
      0 => AccountScreen(onChanged: state.load),
      1 => ResponderRecordsScreen(onChanged: state.load),
      2 => PendingSubmissionsScreen(onRecovered: state.load),
      _ => const SearchScreen(driver: true),
    };
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final state = ResponderScope.of(context);
    final palette = MdrrmoColors.of(context);
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
              const LogoMark(size: 28),
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
                    Text(
                      state.isDriver ? 'Driver & Responder' : 'Responder',
                      overflow: TextOverflow.ellipsis,
                      style: MdrrmoTypography.labelSm.copyWith(
                        color: palette.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
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
          border: Border(top: BorderSide(color: palette.border)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (index) => setState(() => _index = index),
          backgroundColor: palette.surface,
          indicatorColor: palette.brandTint,
          labelPadding: EdgeInsets.zero,
          destinations: [
            NavigationDestination(
              icon: Icon(AppIcons.ambulance, color: palette.textMuted),
              selectedIcon: Icon(AppIcons.ambulance, color: palette.brand),
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
      child: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                TickerMode(
                  enabled: _index == 0,
                  child: LocationAccessGate(
                    onAccessChanged: widget.onLocationAccessChanged,
                    child: HomeScreen(
                      realtime: widget.realtime,
                      tracking: widget.tracking,
                    ),
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
