import 'package:omninest/core/widgets/workstation_pagination_bar.dart';
import 'dart:math' as math;
import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/module_entry_refresh_listener.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/realtime_providers.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/errors/user_facing_error_l10n.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/download_url_opener.dart';
import 'package:omninest/core/utils/file_saver.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/app/theme/mobile_env_theme.dart';
import 'package:omninest/app/mobile_shell/mobile_environment_scope.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/core/widgets/mobile_sample_kit.dart';
import 'package:omninest/features/files/presentation/widgets/file_env_glyph.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/animated_switcher_semantics.dart';
import 'package:omninest/core/widgets/app_form_factor.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/core/widgets/hosted_touch_canvas.dart';
import 'package:omninest/core/widgets/workbench_top_bar.dart';
import 'package:omninest/core/widgets/workbench_navigation_bar.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_status_kit.dart';
import 'package:omninest/core/widgets/mobile_sheet_semantics.dart';
import 'package:omninest/platform/file_pick.dart';

import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/notifications/notification_ui.dart';
import 'package:omninest/core/widgets/font_scale_control.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:omninest/core/widgets/workstation_portal_link.dart';
import 'package:omninest/core/widgets/space_selector_sheet.dart';
import 'package:omninest/core/widgets/responsive_search_field.dart';
import 'package:omninest/core/widgets/top_bar_search_focus.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_operation.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/features/files/presentation/widgets/file_grid.dart';
import 'package:omninest/features/files/presentation/widgets/file_list.dart';
import 'package:omninest/features/files/presentation/pages/file_preview_page.dart';
import 'package:omninest/features/files/presentation/widgets/file_drop_upload_surface.dart';
import 'package:omninest/features/files/presentation/widgets/external_storage_account_dialog.dart';
import 'package:omninest/features/files/presentation/widgets/file_node_actions.dart';
import 'package:omninest/features/files/presentation/widgets/shared_folder_browser.dart';
import 'package:omninest/features/files/presentation/widgets/files_check_mark.dart';
import 'package:omninest/features/files/presentation/widgets/files_dialog.dart';
import 'package:omninest/features/files/presentation/widgets/files_table_view.dart';
import 'package:omninest/features/files/presentation/widgets/hover_horizontal_scroll.dart';
import 'package:omninest/features/files/presentation/widgets/file_inspector_panel.dart';
import 'package:omninest/features/files/presentation/widgets/files_toolbar_control.dart';
import 'package:omninest/features/files/presentation/widgets/share_link_sheet.dart';
import 'package:omninest/features/files/presentation/theme/files_workstation_theme.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/core/utils/clipboard_writer.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
import 'package:url_launcher/url_launcher.dart';

part 'files_operation_l10n.dart';
part 'file_browser_page_navigation.dart';
part 'file_browser_page_workspace.dart';
part 'file_browser_page_upload.dart';
part 'file_browser_page_sharing.dart';
part 'file_browser_page_external.dart';
part 'file_browser_page_batch.dart';
part 'file_browser_page_subpage.dart';
part 'file_browser_page_share_workspaces.dart';
part 'file_browser_page_transfer_workspaces.dart';
part 'file_browser_page_inspector.dart';
part 'file_browser_page_folder_picker.dart';
part 'file_browser_page_dialogs.dart';
part 'file_browser_page_mobile_actions.dart';
part 'file_browser_page_mobile_home.dart';
part 'file_mobile_folder_view.dart';
part 'file_mobile_section_views.dart';
part 'file_mobile_upload_queue.dart';
part 'file_mobile_shares_page.dart';
part 'file_browser_page_storage_stats.dart';
part 'file_browser_page_meta.dart';
part 'file_browser_page_top_bar.dart';
part 'file_browser_page_workspace_rows.dart';
part 'file_browser_page_workspace_preview.dart';
part 'file_browser_page_mobile_tools.dart';

class FileBrowserPage extends ConsumerStatefulWidget {
  const FileBrowserPage({
    super.key,
    this.initialSection,
    this.initialOAuthStatus,
  });

  final FileManagerSection? initialSection;

  /// 外部存储 OAuth 回调状态（success/error）；只消费一次。
  final String? initialOAuthStatus;

  @override
  ConsumerState<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends ConsumerState<FileBrowserPage> {
  /// 已处理过的深链分区：同一分区不再重复进入，否则用户从子页返回模块首页后
  /// 会被 build 再次弹回子页（「退不出去」）。widget.initialSection 变化时复位。
  FileManagerSection? _handledInitialSection;

  @override
  void initState() {
    super.initState();
    scheduleFileOAuthStatusFeedback(
      context: context,
      ref: ref,
      status: widget.initialOAuthStatus,
    );
  }

  /// 深链进来的那一帧：state 还没换成目标分区，先按子页渲染，
  /// 否则顶栏与底部 tab 会在家页面闪一帧再收起。回首页时清除。
  bool _deepLinkedSubpage = false;
  final List<FileManagerSection> _sectionHistory = [];
  FileManagerSection? _lastSection;

  /// 移动首页态：true 时显示位置/分区卡首页。状态源是
  /// [FileBrowserState.mobileSubpage]——壳层要据此收起顶栏与底部 tab，
  /// 留在 Widget 里壳层就读不到。
  bool get _mobileHomeOpen =>
      ref.read(fileBrowserControllerProvider).asData?.value.mobileSubpage !=
      true;

  void _onSectionChanged(FileManagerSection section) {
    if (_lastSection != null && _lastSection != section) {
      _sectionHistory.add(_lastSection!);
    }
    _lastSection = section;
    ref.read(fileBrowserControllerProvider.notifier).loadSection(section);
  }

  void _onBack() {
    // 托管窄屏：先逐级回目录，再回模块首页，最后才走 section 历史栈 → 门户。
    final hosted = MobileShellScope.isHosted(context);
    final narrow = MediaQuery.sizeOf(context).width < 1100;
    final current = ref.read(fileBrowserControllerProvider).asData?.value;
    // 目录层级只在「全部文件」里成立：切到最近/收藏/共享时 breadcrumbs
    // 不会清空，拿它回退会把用户强切回全部文件（进不去也退不出的观感）。
    // 根是空列表不是根节点：一级目录 = length 1，必须一并处理，否则一级目录下
    // 返回会直接离站，再按一次就是分支首路由的 bubble → 引擎退出应用。
    // 多选是最内一层，先于目录与页面层级：一次侧滑只退出多选，
    // 不把「清选中」和「离开子页」压在同一次手势里。
    // 多选是最内一层，先于目录与页面层级：一次侧滑只退出多选，
    // 不把「清选中」和「离开子页」压在同一次手势里。
    if (hosted && current != null && current.hasSelection) {
      ref.read(fileBrowserControllerProvider.notifier).clearSelection();
      return;
    }
    if (hosted &&
        current != null &&
        current.section == FileManagerSection.allFiles &&
        current.breadcrumbs.isNotEmpty) {
      final crumbs = current.breadcrumbs;
      if (crumbs.length > 1) {
        unawaited(
          ref
              .read(fileBrowserControllerProvider.notifier)
              .goToBreadcrumb(crumbs.length - 2),
        );
      } else {
        unawaited(ref.read(fileBrowserControllerProvider.notifier).goToRoot());
      }
      return;
    }
    if (hosted && narrow && !_mobileHomeOpen) {
      // 回到首页即回到导航根：清空分区历史栈，首页态的返回直接离站，
      // 否则历史栈残留会让返回做一次不可见的分区回退（返回键失灵观感）。
      _sectionHistory.clear();
      ref.read(fileBrowserControllerProvider.notifier).setMobileSubpage(false);
      _deepLinkedSubpage = false;
      return;
    }
    if (_sectionHistory.isNotEmpty) {
      final prev = _sectionHistory.removeLast();
      _lastSection = prev;
      ref.read(fileBrowserControllerProvider.notifier).loadSection(prev);
    } else {
      context.go('/portal');
    }
  }

  /// 从首页打开分区：进入列表态。
  void _openMobileSection(FileManagerSection section) {
    _onSectionChanged(section);
    ref.read(fileBrowserControllerProvider.notifier).setMobileSubpage(true);
  }

  /// 从首页内联列表直接进入工作区（不切换分区，保留当前列表态）。
  void _enterMobileWorkspace() {
    ref.read(fileBrowserControllerProvider.notifier).setMobileSubpage(true);
  }

  @override
  void didUpdateWidget(covariant FileBrowserPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSection != oldWidget.initialSection) {
      // 深链再次指向别的分区：闩锁必须复位，否则第二次进入是静默空操作
      // （go_router 的 page key 只认路径，`?section=` 变化走的是原地更新）。
      _handledInitialSection = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filesState = ref.watch(fileBrowserControllerProvider);
    final target = widget.initialSection;
    if (target != null && _handledInitialSection != target) {
      final data = filesState.asData?.value;
      if (data != null) {
        // 认领即消费：同一分区只处理一次，否则用户从子页返回模块首页后
        // build 会再次把它弹回子页（退不出去）。
        _handledInitialSection = target;
        if (data.section != target) {
          _deepLinkedSubpage = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final controller = ref.read(fileBrowserControllerProvider.notifier);
            controller.setMobileSubpage(true);
            controller.loadSection(target);
          });
        } else if (!data.mobileSubpage) {
          // 已是目标分区但停在模块首页（回首页后再点同一入口）：直接进子页。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref
                .read(fileBrowserControllerProvider.notifier)
                .setMobileSubpage(true);
          });
        }
      }
    }
    return ModuleEntryRefreshListener(
      modulePath: '/files',
      onRefresh:
          () => unawaited(
            ref
                .read(fileBrowserControllerProvider.notifier)
                .refreshForRealtime(),
          ),
      child: filesState.when(
        data: (state) {
          _lastSection ??= state.section;
          return _FileManagerShell(
            state: state,
            onBack: _onBack,
            onSectionChanged: _onSectionChanged,
            mobileHomeOpen: !(state.mobileSubpage || _deepLinkedSubpage),
            onOpenMobileSection: _openMobileSection,
            onEnterMobileWorkspace: _enterMobileWorkspace,
          );
        },
        error:
            (error, stackTrace) => Scaffold(
              body: AppErrorView(
                message: AppLocalizations.of(
                  context,
                ).localizeUserFacing(describeUserFacingError(error)),
                onRetry: () => ref.invalidate(fileBrowserControllerProvider),
              ),
            ),
        loading: () => const Scaffold(body: AppLoading()),
      ),
    );
  }
}

class _FileManagerShell extends ConsumerStatefulWidget {
  const _FileManagerShell({
    required this.state,
    required this.onBack,
    required this.onSectionChanged,
    required this.mobileHomeOpen,
    required this.onOpenMobileSection,
    required this.onEnterMobileWorkspace,
  });

  final FileBrowserState state;
  final VoidCallback onBack;
  final void Function(FileManagerSection) onSectionChanged;

  /// 移动首页态与其打开分区的回调（仅托管窄屏使用）。
  final bool mobileHomeOpen;
  final void Function(FileManagerSection) onOpenMobileSection;
  final VoidCallback onEnterMobileWorkspace;

  @override
  ConsumerState<_FileManagerShell> createState() => _FileManagerShellState();
}

class _FileManagerShellState extends ConsumerState<_FileManagerShell> {
  /// 窄屏贴底抽屉是否在场（防止 listen 重复弹层）。
  bool _inspectorSheetOpen = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final hosted = MobileShellScope.isHosted(context);
    ref.listen(
      fileBrowserControllerProvider.select(
        (async) => async.asData?.value.inspectedFileId,
      ),
      (previous, next) {
        if (!mounted) {
          return;
        }
        // 常驻 dock 仅在 ≥1440 的工作位出现；中窄宽度检视改走贴底
        // 抽屉，避免侧栏+抽屉挤压表格造成列溢出（skill 自适应形态）。
        final wide =
            MediaQuery.sizeOf(context).width >=
                FilesInspectorAdaptive.dockMinWidth &&
            !MobileShellScope.isHosted(context);
        if (next == null) {
          _closeInspectorSheet();
          return;
        }
        if (!FilesInspectorAdaptive.sectionHasFileList(widget.state.section)) {
          return;
        }
        if (!wide && !_inspectorSheetOpen) {
          unawaited(_showInspectorSheet(controller));
        }
      },
    );
    final content = LayoutBuilder(
      builder: (context, constraints) {
        // 桌面侧栏路径仅非托管窗口使用；托管态（手机/平板）一律走触屏布局。
        // 阈值与 DesktopFormMinWidth 同源于 ResponsiveBreakpoints.workbenchRail。
        final isWide =
            omniCanvasFormOf(context, constraints) ==
            OmniCanvasForm.desktopRail;
        final currentDest = _destinationForSection(state.section);
        final selectedIndex =
            currentDest != null
                ? _FileNavDestination.values.indexOf(currentDest)
                : 0;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            widget.onBack();
          },
          child: FilesWorkstationScope(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              extendBody: true,
              body: Stack(
                children: [
                  if (!hosted) const _FileBackdrop(),
                  // 主内容（延伸到顶部栏下方）
                  Padding(
                    padding: EdgeInsets.only(
                      top: hosted ? 0 : WorkbenchTopBar.totalHeightOf(context),
                    ),
                    // 托管态触屏内容按壳层 chrome 同宽封顶居中：平板宽度下
                    // 卡片行/列表行不被整屏拉伸，与底栏 tab 组同语言。
                    child: HostedTouchCanvas(
                      hosted: hosted,
                      maxContentWidth: MobileLayoutTokens.chromeMaxWidth,
                      child: Column(
                        children: [
                          if (hosted && !isWide && !widget.mobileHomeOpen) ...[
                            _MobileFolderHeader(
                              state: state,
                              controller: controller,
                              onBack: widget.onBack,
                            ),
                            if (state.section.isSampleFeaturePage)
                              _FeatureSectionHero(section: state.section)
                            else if (_isMobileFolderSection(state.section))
                              _MobileFolderSegments(state: state)
                            else
                              const SizedBox(height: 8),
                            if (_isMobileFolderSection(state.section) &&
                                state.section == FileManagerSection.allFiles &&
                                state.breadcrumbs.length > 1)
                              _MobileGoUpBar(
                                parentName:
                                    state
                                        .breadcrumbs[state.breadcrumbs.length -
                                            2]
                                        .name,
                                onTap:
                                    () => unawaited(
                                      _runFileAction(
                                        context,
                                        () => ref
                                            .read(
                                              fileBrowserControllerProvider
                                                  .notifier,
                                            )
                                            .goToBreadcrumb(
                                              state.breadcrumbs.length - 2,
                                            ),
                                      ),
                                    ),
                              ),
                            if (state.section == FileManagerSection.sharedSpace)
                              _MobileShareManageEntry(
                                onTap:
                                    () => unawaited(
                                      _runFileAction(
                                        context,
                                        () => controller.loadSection(
                                          FileManagerSection.myShares,
                                        ),
                                      ),
                                    ),
                              ),
                          ],
                          if (state.lastActionError case final error?)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                              child: _FileActionStatusBar(
                                error: error,
                                onDismissError:
                                    () =>
                                        ref
                                            .read(
                                              fileBrowserControllerProvider
                                                  .notifier,
                                            )
                                            .clearActionError(),
                              ),
                            ),
                          if (isWide)
                            Expanded(
                              child: Row(
                                children: [
                                  _FileSidebar(
                                    state: state,
                                    enabled: true,
                                    onSectionChanged:
                                        (section) => unawaited(
                                          _runFileAction(
                                            context,
                                            () =>
                                                controller.loadSection(section),
                                          ),
                                        ),
                                  ),
                                  Expanded(
                                    // 文件工作区自身提供滚动主体，避免外层
                                    // SingleChildScrollView 关闭列表虚拟化。
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        34,
                                        26,
                                        34,
                                        40,
                                      ),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 1500,
                                        ),
                                        child: _AnimatedSectionBody(
                                          state: state,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isWide &&
                                      MediaQuery.sizeOf(context).width >=
                                          FilesInspectorAdaptive.dockMinWidth &&
                                      FilesInspectorAdaptive.sectionHasFileList(
                                        state.section,
                                      ))
                                    _InspectorDock(state: state),
                                ],
                              ),
                            )
                          else if (hosted && widget.mobileHomeOpen)
                            Expanded(
                              child: _FileMobileHome(
                                state: state,
                                onOpenSection: widget.onOpenMobileSection,
                                onEnterWorkspace: widget.onEnterMobileWorkspace,
                              ),
                            )
                          else
                            Expanded(
                              child: RefreshIndicator(
                                displacement: 40,
                                edgeOffset: 64,
                                strokeWidth: 2.5,
                                color:
                                    hosted
                                        ? context.env.accent
                                        : context.filesColors.onSurfaceVariant,
                                onRefresh: () async {
                                  // 下拉刷新走原地（background）路径：正文若切到
                                  // loading 占位，就会和下拉弧同时出现，同一件事
                                  // 两个动画。已有内容原地换新即可。
                                  await _runFileAction(
                                    context,
                                    () => controller.loadSection(
                                      state.section,
                                      background: true,
                                    ),
                                  );
                                  await Future<void>.delayed(
                                    MotionToken.pageSwitch,
                                  );
                                },
                                child: Padding(
                                  // 托管态无自有底栏，仅按 FAB 悬浮净距预留。
                                  padding: EdgeInsets.fromLTRB(
                                    16,
                                    10,
                                    16,
                                    hosted ? 16 : 112,
                                  ),
                                  child: _AnimatedSectionBody(state: state),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // 顶部工具栏
                  if (!hosted)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _FileTopBar(state: state),
                    ),
                ],
              ),
              // 托管移动态不使用悬浮新建钮：上传/新建入口收敛到目录页
              // 头部与首页工具栏，避免与底栏叠加形成大面积死区。
              floatingActionButton:
                  isWide || state.hasSelection || hosted
                      ? null
                      : _FileMobileCreateButton(
                        state: state,
                        controller: controller,
                      ),
              bottomNavigationBar:
                  isWide || hosted
                      ? null
                      : WorkbenchNavigationBar(
                        currentIndex: selectedIndex,
                        onTap: (i) {
                          final dest = _FileNavDestination.values[i];
                          final section = _defaultSectionForDestination(dest);
                          widget.onSectionChanged(section);
                        },
                        items:
                            _FileNavDestination.values
                                .map(
                                  (dest) => WorkbenchNavigationItem(
                                    icon: dest.icon,
                                    selectedIcon: dest.selectedIcon,
                                    label: dest.labelOf(
                                      AppLocalizations.of(context),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
            ),
          ),
        );
      },
    );
    // 移动壳层样式隔离：托管态把 Files 工位调色板整体重绑为环境玻璃族，
    // 桌面端（非托管）继续使用原始工位皮肤。
    if (hosted) {
      // 环境面：先按壁纸极性注册配色表，模块调色板再从同一极性派生，
      // 否则工位玻璃会停在暗值，与页面其余环境面不同极。
      return MobileEnvironmentScope(
        child: Builder(
          builder:
              (scopeContext) => Theme(
                data: MobileEnvTheme.withFilesInEnv(scopeContext),
                child: content,
              ),
        ),
      );
    }
    return content;
  }

  /// 窄屏贴底抽屉：Inspector 的移动形态（Header/Footer 常驻、Body 滚动、
  /// 视口 85% 上限），关闭即清空检视态。
  Future<void> _showInspectorSheet(FileBrowserController controller) async {
    final context = this.context;
    _inspectorSheetOpen = true;
    // 面板经根导航器呈现，默认落在壳层 Theme 与 MobileShellScope 之外；
    // 在宿主上下文捕获环境后在面板子树内重放。
    final ambience = MobileSheetAmbience.capture(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      shape:
          ambience.hosted
              ? const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              )
              : null,
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
      builder: (sheetContext) {
        return MobileSheetSemantics(
          child: ambience.wrap(
            Consumer(
              builder: (context, sheetRef, _) {
                final state =
                    sheetRef.watch(fileBrowserControllerProvider).asData?.value;
                final node = state?.inspectedNode;
                if (node == null) {
                  return const SizedBox.shrink();
                }
                final favorites =
                    state!.section == FileManagerSection.favorites;
                final actions = _buildFileNodeActions(
                  context,
                  sheetRef,
                  sheetRef.read(fileBrowserControllerProvider.notifier),
                  recycle: state.section == FileManagerSection.recycleBin,
                  favorites: favorites,
                );
                return Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.85,
                  ),
                  margin: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  decoration: BoxDecoration(
                    // 托管态环境重绑后的 surfaceContainer 是玻璃半透明，
                    // 贴底抽屉需实底（样例 glass-sheet #171E1C）。
                    color:
                        MobileShellScope.isHosted(context)
                            ? context.env.sheetSolid
                            : context.filesColors.surfaceContainer,
                    border: Border(
                      top: BorderSide(
                        color: context.filesColors.selectedBorder,
                      ),
                    ),
                  ),
                  child: FileInspectorPanel(
                    file: node,
                    actions: actions,
                    onClose:
                        () =>
                            sheetRef
                                .read(fileBrowserControllerProvider.notifier)
                                .clearInspection(),
                  ),
                );
              },
            ),
          ),
        );
      },
    ).whenComplete(() {
      // 抽屉退场动画期间页面可能被弹掉或切走：此处既写 State 字段又读 ref，
      // 未挂载时访问会抛 ref-after-unmount（同文件 _closeInspectorSheet 同判据）。
      if (!mounted) {
        return;
      }
      _inspectorSheetOpen = false;
      final current = ref.read(fileBrowserControllerProvider).asData?.value;
      if (current?.inspectedFileId != null) {
        ref.read(fileBrowserControllerProvider.notifier).clearInspection();
      }
    });
  }

  void _closeInspectorSheet() {
    if (!_inspectorSheetOpen || !mounted) {
      return;
    }
    _inspectorSheetOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }
}
