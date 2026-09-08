import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/features/photos/domain/photo.dart';

/// 展示照片编辑页标题和页面级命令。
class PhotoEditorTopBar extends StatelessWidget {
  const PhotoEditorTopBar({
    required this.photo,
    required this.saving,
    required this.onBack,
    required this.onSave,
    required this.onShowVersions,
    super.key,
  });

  final PhotoItem photo;
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onSave;
  final VoidCallback onShowVersions;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16),
      decoration: BoxDecoration(
        color: context.photosColors.surfaceContainer.withValues(
          alpha: compact ? 0.98 : 0.70,
        ),
        border: Border(
          bottom: BorderSide(
            color: context.photosColors.outlineVariant.withValues(alpha: 0.32),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: AppLocalizations.of(context).photosBack,
            onPressed: onBack,
            icon: Icon(
              Icons.arrow_back_rounded,
              color: context.photosColors.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context).photosEditTitle(photo.title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.photosColors.onSurface,
                fontSize: AppTypography.titleMedium,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (compact) ...[
            IconButton(
              onPressed: onShowVersions,
              icon: const Icon(Icons.history_rounded),
              tooltip: AppLocalizations.of(context).photosVersionHistory,
            ),
            IconButton.filled(
              onPressed: saving ? null : onSave,
              icon:
                  saving
                      ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.save_rounded),
              tooltip: AppLocalizations.of(context).photosSave,
            ),
          ] else ...[
            TextButton.icon(
              onPressed: onShowVersions,
              icon: const Icon(Icons.history_rounded, size: 18),
              label: Text(AppLocalizations.of(context).photosVersionHistory),
              style: TextButton.styleFrom(
                foregroundColor: context.photosColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: saving ? null : onSave,
              icon:
                  saving
                      ? SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.photosColors.onPrimaryContainer,
                        ),
                      )
                      : const Icon(Icons.save_rounded, size: 18),
              label: Text(AppLocalizations.of(context).photosSave),
              style: FilledButton.styleFrom(
                backgroundColor: context.photosColors.primaryContainer,
                foregroundColor: context.photosColors.onPrimaryContainer,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
