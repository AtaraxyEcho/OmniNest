import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/features/search/domain/search_result.dart';

class SearchResultTile extends StatelessWidget {
  const SearchResultTile({required this.result, super.key});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.globalColors;
    return ListTile(
      onTap: () => _navigate(context),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _typeColor(result.type, context).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          _typeIcon(result.type),
          size: 20,
          color: _typeColor(result.type, context),
        ),
      ),
      title: Text(
        result.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: AppTypography.bodyLarge,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
      ),
      subtitle: Text(
        result.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: AppTypography.bodySmall,
          color: colors.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  void _navigate(BuildContext context) {
    switch (result.type) {
      case 'file':
        // 分支路由用 go 切换空间是预期语义（同级目的地，不留幽灵栈）。
        context.go('/files');
      case 'book':
        // 其余都是壳层之外的根级路由：`go` 会换掉整条导航栈，之后侧滑没有
        // 可弹层，Android 直接结束 Activity（观感是「搜一下就退出」）。
        context.push('/reader/items/${result.id}');
      case 'video':
        context.push('/video/${result.id}');
      case 'photo':
        context.push('/photos/${result.id}');
      case 'music':
        context.push('/music');
      default:
        break;
    }
  }

  IconData _typeIcon(String type) {
    return switch (type) {
      'file' => Icons.insert_drive_file_outlined,
      'book' => Icons.menu_book_outlined,
      'video' => Icons.movie_outlined,
      'photo' => Icons.photo_outlined,
      'music' => Icons.music_note_outlined,
      _ => Icons.search_rounded,
    };
  }

  Color _typeColor(String type, BuildContext context) {
    final colors = context.globalColors;
    return switch (type) {
      'file' => colors.info,
      'book' => colors.warning,
      'video' => colors.tertiary,
      'music' => colors.success,
      _ => colors.onSurfaceVariant,
    };
  }
}
