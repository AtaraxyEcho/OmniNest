import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/widgets/font_scale_control.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/core/widgets/workbench_top_bar.dart';
import 'package:omninest/features/files/media_import_ui.dart';
import 'package:omninest/features/notifications/notification_ui.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_empty_state.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_search_overlay.dart';

/// 阅读模块页面目标，对应模块内一级导航与路由
enum ReaderPageTarget { library, bookshelf, stats, admin }

extension ReaderPageTargetX on ReaderPageTarget {
  /// 对应的模块内路由
  String get location => switch (this) {
    ReaderPageTarget.library => '/reader',
    ReaderPageTarget.bookshelf => '/reader/bookshelf',
    ReaderPageTarget.stats => '/reader/stats',
    ReaderPageTarget.admin => '/reader/admin',
  };

  String localizedLabel(AppLocalizations l10n) => switch (this) {
    ReaderPageTarget.library => l10n.readerNavLibrary,
    ReaderPageTarget.bookshelf => l10n.readerNavBookshelf,
    ReaderPageTarget.stats => l10n.readerNavStats,
    ReaderPageTarget.admin => l10n.readerNavManage,
  };
}

/// 阅读模块页面骨架：模块内页头（下划线 Tab 导航）+ 桌面顶栏 + 内容区。
///
/// 取代旧 ReaderShell 的侧栏与内嵌底部导航；页签切换通过模块内路由完成，
/// 全局壳（移动端顶栏/底部导航、桌面模块顶栏）保持既有职责。
class ReaderPageScaffold extends ConsumerStatefulWidget {
  const ReaderPageScaffold({
    required this.target,
    required this.child,
    this.searchController,
    this.onSearchChanged,
    this.onRefresh,
    this.showImportAction = false,
    super.key,
  });

  final ReaderPageTarget target;

  /// 页面内容（非滚动容器，由骨架负责滚动）
  final Widget child;

  /// 书库搜索控制器；传入后在桌面顶栏内嵌搜索框，窄屏提供搜索弹窗入口
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;

  final Future<void> Function()? onRefresh;

  /// 是否在顶栏展示快速导入按钮
  final bool showImportAction;

  @override
  ConsumerState<ReaderPageScaffold> createState() => _ReaderPageScaffoldState();
}

class _ReaderPageScaffoldState extends ConsumerState<ReaderPageScaffold> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authSessionProvider).asData?.value.user;
    final canManage = user?.role == 'SUPER_ADMIN';
    if (widget.target == ReaderPageTarget.admin && !canManage) {
      return _ReaderAdminForbidden();
    }

    final hosted = MobileShellScope.isHosted(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 840;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            context.go(
              widget.target == ReaderPageTarget.library
                  ? '/portal'
                  : ReaderPageTarget.library.location,
            );
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            extendBody: true,
            body: Stack(
              children: [
                if (hosted)
                  const MobilePageSurface(
                    exposeBackdrop: true,
                    backdropOpacity: 0.56,
                    child: SizedBox.expand(),
                  )
                else
                  ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: const SizedBox.expand(),
                  ),
                Padding(
                  padding: EdgeInsets.only(
                    top: hosted ? 0 : WorkbenchTopBar.totalHeightOf(context),
                  ),
                  child: Column(
                    children: [
                      ReaderSectionTabBar(
                        current: widget.target,
                        canManage: canManage,
                      ),
                      Expanded(
                        child: _ReaderPageScrollArea(
                          isWide: isWide,
                          hosted: hosted,
                          onRefresh: widget.onRefresh,
                          child: widget.child,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!hosted)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _ReaderModuleTopBar(
                      target: widget.target,
                      searchController: widget.searchController,
                      onSearchChanged: widget.onSearchChanged,
                      showImportAction: widget.showImportAction,
                      user: user,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 桌面模块顶栏：返回门户 + 页面标题 + 快速导入 + 搜索 + 全局控件入口。
class _ReaderModuleTopBar extends ConsumerWidget {
  const _ReaderModuleTopBar({
    required this.target,
    required this.user,
    this.searchController,
    this.onSearchChanged,
    this.showImportAction = false,
  });

  final ReaderPageTarget target;
  final UserProfile? user;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final bool showImportAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final rc = context.readerColors;
    final isWide = MediaQuery.sizeOf(context).width >= 840;
    final barContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => context.go('/portal'),
            icon: Icon(
              Icons.arrow_back_rounded,
              size: 18,
              color: rc.onSurfaceVariant,
            ),
            label: Text(
              l10n.readerPortal,
              style: TextStyle(
                fontSize: 13,
                height: 18 / 13,
                fontWeight: FontWeight.w700,
                color: rc.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(width: 12),
          Text(
            target.localizedLabel(l10n),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: rc.onSurface,
              fontSize: 16,
              height: 24 / 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          Spacer(),
          if (showImportAction) ...[
            MediaImportButton(
              subsystemDirectory: 'Reader',
              acceptedExtensions: const ['epub', 'txt', 'cbz', 'zip'],
              reuseExistingFiles: true,
              onImportComplete: () {
                ref.read(readerCenterControllerProvider.notifier).refresh();
              },
              style: ImportButtonStyle.iconButton,
              color: rc.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
          ],
          if (!isWide &&
              onSearchChanged != null &&
              searchController != null) ...[
            _SearchIconButton(onSearch: onSearchChanged!, colors: rc),
            const SizedBox(width: 8),
          ] else if (searchController != null && onSearchChanged != null) ...[
            SizedBox(width: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: _ReaderPageSearchField(
                controller: searchController!,
                onChanged: onSearchChanged!,
              ),
            ),
            const SizedBox(width: 16),
          ],
          if (isWide) ...[
            FontScaleControl(size: 20, color: rc.onSurfaceVariant),
            NotificationIcon(size: 20, color: rc.onSurfaceVariant),
            const SizedBox(width: 8),
          ],
          const UserAvatarMenu(),
        ],
      ),
    );

    return WorkbenchTopBar(
      surfaceColor: rc.surface,
      borderColor: rc.outlineVariant,
      child: barContent,
    );
  }
}

/// 模块内页头 Tab：下划线样式，切换通过模块内路由完成。
class ReaderSectionTabBar extends StatelessWidget {
  const ReaderSectionTabBar({
    required this.current,
    required this.canManage,
    this.onChanged,
    super.key,
  });

  final ReaderPageTarget current;
  final bool canManage;

  /// 覆盖默认的路由跳转（测试或特殊导航场景使用）
  final ValueChanged<ReaderPageTarget>? onChanged;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final targets = [
      ReaderPageTarget.library,
      ReaderPageTarget.bookshelf,
      ReaderPageTarget.stats,
      if (canManage) ReaderPageTarget.admin,
    ];
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: rc.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            for (final target in targets)
              _ReaderSectionTab(
                target: target,
                selected: target == current,
                onTap: () {
                  if (target == current) return;
                  if (onChanged != null) {
                    onChanged!(target);
                  } else {
                    context.go(target.location);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ReaderSectionTab extends StatelessWidget {
  const _ReaderSectionTab({
    required this.target,
    required this.selected,
    required this.onTap,
  });

  final ReaderPageTarget target;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final label = target.localizedLabel(AppLocalizations.of(context));
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? rc.onSurface : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            height: 18 / 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? rc.onSurface : rc.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 页面内容滚动容器：窄屏带下拉刷新，宽屏固定内边距。
class _ReaderPageScrollArea extends StatelessWidget {
  const _ReaderPageScrollArea({
    required this.isWide,
    required this.hosted,
    required this.child,
    this.onRefresh,
  });

  final bool isWide;
  final bool hosted;
  final Widget child;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    if (hosted && !isWide) {
      return RefreshIndicator(
        displacement: 40,
        edgeOffset: 64,
        strokeWidth: 2.5,
        color: context.mobileColors.musicAccent,
        onRefresh: onRefresh ?? () async {},
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.sizeOf(context).height - 220,
            ),
            child: child,
          ),
        ),
      );
    }
    return RefreshIndicator(
      strokeWidth: 2.5,
      color: rc.primary,
      onRefresh: onRefresh ?? () async {},
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(
          isWide ? 40 : 16,
          isWide ? 20 : 20,
          isWide ? 40 : 16,
          40,
        ),
        child: child,
      ),
    );
  }
}

class _ReaderPageSearchField extends StatelessWidget {
  const _ReaderPageSearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(
        color: context.readerColors.onSurface,
        fontSize: 13,
        height: 18 / 13,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: context.readerColors.surfaceContainerHigh,
        hintText: AppLocalizations.of(context).readerSearchBooksHint,
        hintStyle: TextStyle(
          color: context.readerColors.onSurfaceVariant,
          fontSize: 13,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: context.readerColors.onSurfaceVariant.withValues(alpha: 0.8),
          size: 20,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(
            color: context.readerColors.primary.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

class _SearchIconButton extends StatelessWidget {
  const _SearchIconButton({required this.onSearch, required this.colors});

  final ValueChanged<String> onSearch;
  final ReaderColors colors;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: AppLocalizations.of(context).readerSearch,
      icon: Icon(
        Icons.search_rounded,
        size: 22,
        color: colors.onSurfaceVariant,
      ),
      onPressed: () => _showSearchDialog(context),
    );
  }

  void _showSearchDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    // dispose 兜底标记：dialog future 异常中断时控制器也不会重复释放
    var controllerDisposed = false;
    void disposeController() {
      if (controllerDisposed) return;
      controllerDisposed = true;
      controller.dispose();
    }

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: l10n.readerSearch,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder:
          (context, animation, secondaryAnimation) => Dialog(
            backgroundColor: Colors.transparent,
            child: ReaderSearchOverlay(
              controller: controller,
              colors: colors,
              onSearch: (query) {
                if (query.trim().isNotEmpty) {
                  onSearch(query.trim());
                  Navigator.of(context).pop();
                }
              },
            ),
          ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    ).whenComplete(disposeController);
  }
}

/// 管理页无权限兜底视图（页签对非管理员隐藏，直接访问路由时展示）。
class _ReaderAdminForbidden extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: ReaderEmptyState(
          title: l10n.readerMetadataManagement,
          subtitle: l10n.readerManageHint,
          icon: Icons.admin_panel_settings_outlined,
        ),
      ),
    );
  }
}
