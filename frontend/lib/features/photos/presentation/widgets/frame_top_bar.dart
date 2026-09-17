import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/core/widgets/responsive_search_field.dart';
import 'package:omninest/core/widgets/font_scale_control.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/features/files/application/media_import_service.dart';
import 'package:omninest/features/files/media_import_ui.dart';
import 'package:omninest/features/notifications/notification_ui.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_view_meta.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_common_widgets.dart';

/// Frame 顶栏：返回 Portal、衬线视图标题、搜索框与导入、通知、头像入口。
///
/// 多选不提供顶栏按钮，由照片卡片长按进入；回收站与影集视图的
/// 卡片不支持多选。
class FrameTopBar extends ConsumerWidget {
  const FrameTopBar({
    required this.view,
    required this.searchController,
    required this.onSearchChanged,
    required this.showTitle,
    this.searchExpanded = false,
    this.showBack = false,
    this.showImport = true,
    super.key,
  });

  final FrameView view;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  /// 设计稿在 md 以下隐藏衬线标题。
  final bool showTitle;

  /// 设计稿搜索框在 md 以下 flex-1 撑满，md 及以上固定宽度。
  final bool searchExpanded;

  /// 显示返回 Portal 入口；应用壳托管的移动端由壳层导航承担。
  final bool showBack;

  /// 多选模式隐藏导入，避免与批量操作抢焦点（与 File 的 FAB 策略一致）。
  final bool showImport;

  static const double height = 56;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.frameColors;

    // 与其他模块一致的共享搜索框样式。
    Widget searchField = ResponsiveSearchField(
      controller: searchController,
      onChanged: onSearchChanged,
      hintText: l10n.photosSearchHint,
      maxWidth: searchExpanded ? double.infinity : 262,
      style: TextStyle(fontSize: AppTypography.bodyLarge),
      // 设计稿搜索框高 34px（py-1.5 + text-sm 行高 20px + 1px 边框），
      // 与顶栏 34px 图标按钮一致；prefixIcon 默认 48x48 最小约束
      // 会托高输入框，必须显式收窄才能压到目标高度。
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        hintText: l10n.photosSearchHint,
        prefixIcon: const Icon(Icons.search_rounded, size: 14),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 34,
          minHeight: 34,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
    );
    if (searchExpanded) {
      searchField = Expanded(child: searchField);
    }

    // 装饰铺满含状态栏，SafeArea 只避让内容。
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.navBg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: showTitle ? 24 : 16),
            child: Row(
              children: [
                if (showBack) ...[
                  FrameIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: l10n.photosBackToPortal,
                    onTap: () => context.go('/portal'),
                  ),
                  const SizedBox(width: 12),
                ],
                if (showTitle)
                  Text(
                    frameViewLabel(l10n, view),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: FramePalette.serifFamily,
                      fontFamilyFallback: FramePalette.serifFallback,
                      color: colors.ink,
                      fontSize: AppTypography.titleLarge,
                    ),
                  ),
                const Spacer(),
                searchField,
                const SizedBox(width: 12),
                if (showImport) ...[
                  const FrameImportAction(),
                  const SizedBox(width: 12),
                ],
                const FontScaleControl(size: 20),
                const NotificationIcon(size: 20),
                const SizedBox(width: 12),
                const UserAvatarMenu(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Frame 图标按钮：34px 方形、6px 圆角，激活态陶土色高亮，悬停墨色。
class FrameIconButton extends StatefulWidget {
  const FrameIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  State<FrameIconButton> createState() => _FrameIconButtonState();
}

class _FrameIconButtonState extends State<FrameIconButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.frameColors;
    final active = widget.active;
    final background =
        active
            ? colors.selectActiveBg
            : _hovering
            ? colors.hover
            : Colors.transparent;
    final iconColor =
        active
            ? colors.accent
            : _hovering
            ? colors.ink
            : colors.muted;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(widget.icon, size: 18, color: iconColor),
          ),
        ),
      ),
    );
  }
}

/// 照片导入入口：顶栏图标与托管态页签行尾部共用，沿用图库导入完成回调。
///
/// 紧凑档提供 44px 触控目标；保持图标入口而非 FAB（浏览优先，单动作导入）。
class FrameImportAction extends ConsumerWidget {
  const FrameImportAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = ResponsiveBreakpoints.isCompact(
      MediaQuery.sizeOf(context).width,
    );
    return SizedBox(
      width: compact ? 44 : 36,
      height: compact ? 44 : 36,
      child: MediaImportButton(
        subsystemDirectory: 'Photos',
        enableCamera: true,
        acceptedExtensions: const <String>[
          'jpg',
          'jpeg',
          'png',
          'gif',
          'heic',
          'heif',
          'bmp',
          'tif',
          'tiff',
        ],
        unsupportedExtensions: const <String>[],
        onImportComplete: () {},
        onImportCompleteWithResult: (result) async {
          if (!context.mounted) return null;
          final controller = ref.read(photoCenterControllerProvider.notifier);
          final visible = await controller.refreshAfterImport(
            expectedFileIds: result.imported.map((file) => file.fileNodeId),
            taskIds:
                result.imported
                    .map((file) => file.mediaAutoImportTaskId)
                    .whereType<String>(),
          );
          if (!context.mounted) return null;
          final failure = controller.lastImportNotice;
          if (!visible && failure != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  photoImportNoticeText(AppLocalizations.of(context), failure),
                ),
              ),
            );
            return MediaImportCompletionState.failed;
          }
          return visible
              ? MediaImportCompletionState.completed
              : MediaImportCompletionState.processing;
        },
        allowSharedSpace: false,
        reuseExistingFiles: true,
        style: ImportButtonStyle.iconButton,
        color: context.frameColors.muted,
      ),
    );
  }
}
