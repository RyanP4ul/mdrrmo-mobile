import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/resident_state.dart';
import '../../ui/kit.dart';
import '../../ui/logout_action.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'notifications_screen.dart';
import 'report_screen.dart';
import 'schedule_screen.dart';

class ResidentShell extends StatefulWidget {
  const ResidentShell({super.key});
  @override
  State<ResidentShell> createState() => _ResidentShellState();
}

class _ResidentShellState extends State<ResidentShell> {
  int _index = 0;

  void _go(int index) => setState(() => _index = index);

  Future<void> _report(ResidentState state) async {
    if (!state.profile.canSubmit) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => ResidentReportPage(state: state),
      ),
    );
  }

  Future<void> _menu(ResidentState state) async {
    final choice = await showAppSheet<int>(
      context,
      title: 'More options',
      subtitle: 'Records and support',
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
                  subtitle: 'Reload latest updates now',
                  showChevron: true,
                  onTap: () => Navigator.pop(sheetCtx, 1),
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
                  onTap: () => Navigator.pop(sheetCtx, 2),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 1) {
      await state.load();
      return;
    }
    if (choice == 2) {
      await logoutFrom(context);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ResidentScope.of(context);
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
                      'Resident',
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
          onDestinationSelected: _go,
          backgroundColor: palette.surface,
          indicatorColor: palette.brandTint,
          destinations: [
            NavigationDestination(
              icon: Icon(AppIcons.home, color: palette.textMuted),
              selectedIcon: Icon(AppIcons.home, color: palette.brand),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(AppIcons.form, color: palette.textMuted),
              selectedIcon: Icon(AppIcons.form, color: palette.brand),
              label: 'Reports',
            ),
            NavigationDestination(
              icon: Icon(AppIcons.calendar, color: palette.textMuted),
              selectedIcon: Icon(AppIcons.calendar, color: palette.brand),
              label: 'Services',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: state.unreadCount > 0,
                label: Text(
                  state.unreadCount > 99 ? '99+' : '${state.unreadCount}',
                ),
                child: Icon(AppIcons.bell, color: palette.textMuted),
              ),
              selectedIcon: Badge(
                isLabelVisible: state.unreadCount > 0,
                label: Text(
                  state.unreadCount > 99 ? '99+' : '${state.unreadCount}',
                ),
                child: Icon(AppIcons.bell, color: palette.brand),
              ),
              label: 'Updates',
            ),
          ],
        ),
      ),
      child: !state.hasLoaded && state.isLoading
          ? Center(child: CircularProgressIndicator(color: palette.brand))
          : !state.hasLoaded && state.loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: ContentFrame(
                  child: AppStateView(
                    icon: AppIcons.wifiOff,
                    title: 'Could not load your information',
                    message: 'Check your connection and try again.',
                    accent: palette.danger,
                    action: AppButton(label: 'Try again', onPress: state.load),
                  ),
                ),
              ),
            )
          : Column(
              children: [
                if (state.loadError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: AppBanner(
                      tone: AppBannerTone.warning,
                      icon: AppIcons.wifiOff,
                      message:
                          'Could not refresh. Your last updates are shown.',
                      action: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: state.isLoading ? null : state.load,
                          child: const Text('Retry'),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _index,
                    children: [
                      TickerMode(
                        enabled: _index == 0,
                        child: ResidentHomeScreen(
                          onOpenReport: () => _report(state),
                          onOpenReports: () => _go(1),
                          onOpenServices: () => _go(2),
                        ),
                      ),
                      TickerMode(
                        enabled: _index == 1,
                        child: const ResidentHistoryScreen(),
                      ),
                      TickerMode(
                        enabled: _index == 2,
                        child: const ResidentScheduleScreen(),
                      ),
                      TickerMode(
                        enabled: _index == 3,
                        child: const ResidentNotificationsScreen(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// A separate route keeps the report form focused and preserves bottom-tab state.
class ResidentReportPage extends StatelessWidget {
  const ResidentReportPage({super.key, required this.state});
  final ResidentState state;
  @override
  Widget build(BuildContext context) => ResidentScope(
    state: state,
    child: AppScaffold(
      childPad: false,
      header: pushedHeader(context, 'Report an incident'),
      child: ResidentReportScreen(onDone: () => Navigator.of(context).pop()),
    ),
  );
}
