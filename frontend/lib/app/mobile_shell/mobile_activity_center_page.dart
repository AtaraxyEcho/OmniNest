import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_scene_scope.dart';
import 'package:omninest/features/notifications/presentation/pages/notification_page.dart';
import 'package:omninest/features/tasks/presentation/pages/tasks_page.dart';

/// 在应用组合层聚合通知与任务入口，业务状态仍由各 Feature 独立维护。
class MobileActivityCenterPage extends StatelessWidget {
  const MobileActivityCenterPage({this.initialIndex = 0, super.key});

  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppBackdropSceneScope(
      owner: 'app.mobile.activity',
      policy: AppBackdropPolicy.work,
      pathPrefix: '/activity',
      child: DefaultTabController(
        length: 2,
        initialIndex: initialIndex.clamp(0, 1),
        child: Scaffold(
          backgroundColor: context.mobileColors.pageMask,
          appBar: AppBar(
            backgroundColor: context.mobileColors.surface,
            surfaceTintColor: Colors.transparent,
            title: Text(
              l10n.mobileActivityCenter,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            bottom: TabBar(
              indicatorColor: context.mobileColors.musicAccent,
              labelColor: context.mobileColors.textPrimary,
              unselectedLabelColor: context.mobileColors.textSecondary,
              tabs: [
                Tab(text: l10n.notificationTitle),
                Tab(text: l10n.tasksTitle),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              NotificationPage(embedded: true),
              TasksPage(embedded: true),
            ],
          ),
        ),
      ),
    );
  }
}
