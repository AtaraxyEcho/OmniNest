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
        context.go('/files');
      case 'book':
        context.go('/reader/items/${result.id}');
      case 'video':
        context.go('/video/${result.id}');
      case 'photo':
        context.go('/photos/${result.id}');
      case 'music':
        context.go('/music');
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
