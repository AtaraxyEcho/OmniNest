import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/features/photos/domain/photo_edit_version.dart';

/// 展示照片编辑版本，并将回滚动作交给页面协调。
class PhotoVersionListSheet extends StatelessWidget {
  const PhotoVersionListSheet({
    required this.versions,
    required this.onRevert,
    super.key,
  });

  final List<PhotoEditVersion> versions;
  final ValueChanged<String> onRevert;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              AppLocalizations.of(context).photosEditVersionHistory,
              style: TextStyle(
                color: context.photosColors.onSurface,
                fontSize: AppTypography.titleMedium,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (versions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                AppLocalizations.of(context).photosNoEditHistory,
                style: TextStyle(color: context.photosColors.onSurfaceVariant),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: versions.length,
                itemBuilder: (context, index) {
                  final version = versions[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: context.photosColors.primaryContainer
                          .withValues(alpha: 0.14),
                      child: Text(
                        'v${version.versionNumber}',
                        style: TextStyle(
                          color: context.photosColors.primaryContainer,
                          fontSize: AppTypography.bodySmall,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    title: Text(
                      _editTypeLabel(
                        AppLocalizations.of(context),
                        version.editType,
                      ),
                      style: TextStyle(color: context.photosColors.onSurface),
                    ),
                    subtitle: Text(
                      _formatCreatedAt(version.createdAt),
                      style: TextStyle(
                        color: context.photosColors.onSurfaceVariant,
                      ),
                    ),
                    trailing: TextButton(
                      onPressed: () => onRevert(version.id),
                      child: Text(AppLocalizations.of(context).photosRollback),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  String _formatCreatedAt(DateTime? createdAt) {
    if (createdAt == null) {
      return '';
    }
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${createdAt.year}-${twoDigits(createdAt.month)}-'
        '${twoDigits(createdAt.day)} ${twoDigits(createdAt.hour)}:'
        '${twoDigits(createdAt.minute)}';
  }
}

String _editTypeLabel(AppLocalizations l10n, String editType) {
  return switch (editType) {
    'ROTATE' => l10n.photosEditTypeRotate,
    'CROP' => l10n.photosEditTypeCrop,
    'BRIGHTNESS' => l10n.photosEditTypeBrightness,
    'CONTRAST' => l10n.photosEditTypeContrast,
    'FILTER' => l10n.photosEditTypeFilter,
    _ => editType,
  };
}
