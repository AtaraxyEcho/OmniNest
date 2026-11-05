import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/features/search/domain/search_result.dart';
import 'package:omninest/features/video/domain/movie_detail_routes.dart';

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
        // 命中项只有文件 ID：先进预览路由回源节点，落到 /files 根目录等于
        // 把用户丢回列表，还得自己再找一遍。预览与其余详情页同为根级路由，
        // 用 push 才有可弹层。
        context.push('/files/preview/${result.id}');
      case 'book':
        // 其余都是壳层之外的根级路由：`go` 会换掉整条导航栈，之后侧滑没有
        // 可弹层，Android 直接结束 Activity（观感是「搜一下就退出」）。
        context.push('/reader/items/${result.id}');
      case 'video':
        // 分集进剧集详情选集；用分集 id 拼影片详情会打开错误条目。
        context.push(
          movieDetailRouteFromIds(
            videoItemId: result.id,
            seriesId: result.seriesId,
          ),
        );
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
