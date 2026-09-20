import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/portal/application/portal_dashboard_providers.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_desktop_visual_shells.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_mobile_shell.dart';

class PortalPage extends ConsumerStatefulWidget {
  const PortalPage({super.key});

  @override
  ConsumerState<PortalPage> createState() => _PortalPageState();
}

/// Portal 宿主：负责摘要数据的及时同步。
///
/// 四条刷新路径均为节流驱动：进入页面时（仅重进，跳过首次加载）、分支
/// 重返时（StatefulShellRoute 下 Portal 常驻挂载，initState 不会重跑，
/// 监听路由 URI 以 2 秒节流补一次刷新）、窗口重新聚焦时（30 秒节流），
/// 以及实时脏范围订阅（由 [portalDashboardRealtimeBinderProvider] 承载，
/// 页面挂载期间存活）。不做定时轮询：协调器的周期同步会把离线期间
/// 漏掉的推送以脏范围补发。
class _PortalPageState extends ConsumerState<PortalPage>
    with WidgetsBindingObserver {
  VoidCallback? _routeListener;
  GoRouter? _router;
  DateTime _lastBranchRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(ref.read(portalDashboardActionsProvider).refreshOnEntry());
      // 布局测试等场景可能没有路由器，跳过分支重返监听。
      final router = GoRouter.maybeOf(context);
      if (router == null) {
        return;
      }
      _router = router;
      void listener() {
        final path = router.routeInformationProvider.value.uri.path;
        if (path == '/portal' && mounted) {
          final now = DateTime.now();
          if (now.difference(_lastBranchRefresh).inMilliseconds > 2000) {
            _lastBranchRefresh = now;
            final actions = ref.read(portalDashboardActionsProvider);
            unawaited(actions.refreshOnEntry());
            // 封面关键分区不受全量 30s 节流：模块往返后即使全量被
            // 节流跳过，迷你卡封面也能拿到现签 URL。
            unawaited(actions.refreshCoverSections());
          }
        }
      }

      _routeListener = listener;
      router.routeInformationProvider.addListener(listener);
    });
  }

  @override
  void dispose() {
    if (_routeListener != null && _router != null) {
      _router!.routeInformationProvider.removeListener(_routeListener!);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(portalDashboardActionsProvider).maybeRefreshAll());
    }
  }

  @override
  Widget build(BuildContext context) {
    // 挂载期间订阅实时脏范围；autoDispose 保证离开页面即取消。
    ref.watch(portalDashboardRealtimeBinderProvider);
    final isCompact = ResponsiveBreakpoints.isCompact(
      MediaQuery.sizeOf(context).width,
    );
    final policy =
        isCompact ? AppBackdropPolicy.portalMobile : AppBackdropPolicy.portal;
    final content = Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = !ResponsiveBreakpoints.isCompact(constraints.maxWidth);
          if (!isWide) {
            return const PortalMobileShell();
          }
          return const PortalDesktopVisualHost();
        },
      ),
    );
    if (MobileShellScope.isHosted(context)) {
      return content;
    }
    return AppBackdropSceneScope(
      owner: 'portal',
      policy: policy,
      pathPrefix: '/portal',
      child: content,
    );
  }
}
