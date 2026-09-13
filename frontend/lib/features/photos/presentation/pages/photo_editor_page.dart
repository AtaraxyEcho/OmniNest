import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/navigation/navigation_extensions.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_editor_configs.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

/// 照片编辑页面：基于 pro_image_editor 的整图编辑（裁剪/滤镜/调参等）。
///
/// 编辑完成后将产出的整图字节提交后端，保存为新的编辑版本（可回滚）。
class PhotoEditorPage extends ConsumerWidget {
  const PhotoEditorPage({required this.photoId, super.key});

  final String photoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoAsync = ref.watch(photoDetailProvider(photoId));
    return photoAsync.when(
      data:
          (photo) =>
              photo.hasCover || photo.sourceUrl != null
                  // 编辑器内部 SafeArea 会把手势导航区让出；外层铺满纯黑，
                  // 避免路由透明背景把 Portal 背景从底栏空隙露出来。
                  ? Scaffold(
                    backgroundColor: Colors.black,
                    body: ProImageEditor.network(
                      photo.sourceUrl ?? photo.coverUrl!,
                      configs: buildPhotoEditorConfigs(
                        AppLocalizations.of(context),
                      ),
                      callbacks: ProImageEditorCallbacks(
                        onImageEditingComplete: (bytes) async {
                          await _saveEditedImage(context, ref, bytes);
                        },
                        onCloseEditor:
                            (_) => context.popOrGo('/photos/$photoId'),
                      ),
                    ),
                  )
                  : Scaffold(
                    backgroundColor: Colors.black,
                    body: Center(
                      child: Icon(
                        Icons.photo_outlined,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 64,
                      ),
                    ),
                  ),
      error:
          (error, _) => Scaffold(
            appBar: AppBar(
              leading: IconButton(
                tooltip: AppLocalizations.of(context).photosBackToPhotos,
                onPressed: () => context.popOrGo('/photos/$photoId'),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            body: AppErrorView(
              message: describeUserFacingError(error).displayMessage,
              onRetry: () => ref.invalidate(photoDetailProvider(photoId)),
            ),
          ),
      loading: () => const Scaffold(body: Center(child: AppLoading.detail())),
    );
  }

  /// 提交编辑结果；成功后由 onCloseEditor 返回详情页，失败时停留编辑器并提示。
  Future<void> _saveEditedImage(
    BuildContext context,
    WidgetRef ref,
    Uint8List bytes,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .applyEditedImage(photoId, bytes);
      ref.invalidate(photoDetailProvider(photoId));
      messenger.showSnackBar(SnackBar(content: Text(l10n.photosEditSaved)));
    } on Exception {
      messenger.showSnackBar(SnackBar(content: Text(l10n.photosSaveFailed)));
      rethrow;
    }
  }
}
