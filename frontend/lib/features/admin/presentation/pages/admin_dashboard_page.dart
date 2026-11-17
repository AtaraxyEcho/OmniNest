import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_section.dart';
import 'package:omninest/features/admin/presentation/pages/admin_group_pages.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_shell.dart';

/// 管理控制台主页面。
///
/// 深链分区：`/admin/:section`。样例只有 5 个导航分区（Overview / Identity /
/// Operations / Configuration / Storage），旧的 10 个段保留为别名并落到对应
/// 容器页签，避免书签与既有测试失效。
class AdminDashboardPage extends ConsumerStatefulWidget {
  const AdminDashboardPage({this.initialSectionSegment, super.key});

  /// 路由路径段，如 `identity`、`ops`、`storage`；空或非法时回落 overview。
  final String? initialSectionSegment;

  @override
  ConsumerState<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends ConsumerState<AdminDashboardPage> {
  late AdminSection _section;

  @override
  void initState() {
    super.initState();
    _section = AdminSection.fromPathSegment(widget.initialSectionSegment);
    // 进入即查由页面挂载统一承担：失效目标分区常驻缓存；未创建的
    // provider 失效为空操作，挂载后仅取数一次。
    _invalidateSectionAfterFrame(_section);
  }

  @override
  void didUpdateWidget(covariant AdminDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSectionSegment != widget.initialSectionSegment) {
      final next = AdminSection.fromPathSegment(widget.initialSectionSegment);
      if (next != _section) {
        setState(() => _section = next);
        _invalidateSectionAfterFrame(next);
      }
    }
  }

  /// 失效必须推迟到本帧之后：initState/didUpdateWidget 都处于构建期，
  /// 此时弄脏侧栏也在监听的常驻 provider，兄弟节点稍后 watch 该 provider
  /// 会同步刷新并回灌侧栏，触发 setState() during build。
  void _invalidateSectionAfterFrame(AdminSection section) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(adminSectionRefreshProvider).invalidate(section);
    });
  }

  /// 容器内页签切换：沿用旧段的深链，外壳据此同步滚动策略。
  void _onTabChanged(AdminSection section) {
    if (section == _section) return;
    context.go(section.location);
  }

  void _onSectionChanged(AdminSection section) {
    if (section == _section) {
      return;
    }
    final target = section.group.location;
    final uri = GoRouterState.of(context).uri.toString();
    if (uri == target) {
      // URL 已与目标一致（深链回绕）：本地切分区并失效缓存。
      setState(() => _section = section);
      ref.read(adminSectionRefreshProvider).invalidate(section);
      return;
    }
    // 分区切换与缓存失效统一由路由驱动（initState/didUpdateWidget）。
    // 首次点击跨 /admin → /admin/:section 路由会整页替换：若此处先
    // setState，退出中的旧页与进入的新页会各挂载一次目标分区，
    // autoDispose 分区被创建两次，形成首次点击的二次加载。
    context.go(target);
  }

  @override
  Widget build(BuildContext context) {
    final permissions =
        ref.watch(authSessionProvider).value?.user?.permissions ??
        const <String>{};
    // 当前页签不可见时，容器会自动改选同分组里第一个有权限的页签；
    // 整个分组都不可见才显示无权限。
    final groupVisible =
        AdminSection.visibleInGroup(_section.group, permissions).isNotEmpty;
    if (!groupVisible) {
      return AdminShell(
        section: _section,
        onSectionChanged: _onSectionChanged,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              AppLocalizations.of(context).adminSectionForbidden,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return AdminShell(
      section: _section,
      onSectionChanged: _onSectionChanged,
      child: AdminGroupPage(
        group: _section.group,
        initialSection: _section,
        onTabChanged: _onTabChanged,
      ),
    );
  }
}
