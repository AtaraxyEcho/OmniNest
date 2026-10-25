import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';

import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/navigation/navigation_extensions.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_editor_configs.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';

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
                        context.env,
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
                    backgroundColor: context.env.stage,
                    appBar: AppBar(
                      backgroundColor: Colors.transparent,
                      foregroundColor: context.env.ink,
                      leading: IconButton(
                        tooltip:
                            AppLocalizations.of(context).photosBackToPhotos,
                        onPressed: () => context.popOrGo('/photos/$photoId'),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    body: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.photo_outlined,
                            color: context.env.ink.withValues(alpha: 0.4),
                            size: 64,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            AppLocalizations.of(
                              context,
                            ).photosEditSourceUnavailable,
                            style: TextStyle(color: context.env.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
      error:
          (error, _) => Scaffold(
            // 本路由未经 MobileHostedRoute 包裹，浅色根主题下要把底色与
            // 返回钮显式压回环境暗底，否则错误面闪白。
            backgroundColor: context.env.stage,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: context.env.ink,
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
      loading:
          () => const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: AppLoading()),
          ),
    );
  }

  /// 提交编辑结果；成功后由 onCloseEditor 返回详情页，失败时停留编辑器并提示。
  Future<void> _saveEditedImage(
    BuildContext context,
    WidgetRef ref,
    Uint8List bytes,
  ) async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    // 整图上传可能耗时数秒；保存期间用不可取消的遮罩明确告知正在提交。
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder:
            (_) => const PopScope(
              canPop: false,
              child: Center(child: AppLoading()),
            ),
      ),
    );
    void dismissSavingOverlay() {
      if (navigator.mounted) {
        navigator.pop();
      }
    }

    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .applyEditedImage(photoId, bytes);
      dismissSavingOverlay();
      if (!context.mounted) {
        return;
      }
      ref.invalidate(photoDetailProvider(photoId));
      showOmniFeedback(
        context,
        l10n.photosEditSaved,
        severity: OmniFeedbackSeverity.success,
      );
    } on Object catch (error) {
      dismissSavingOverlay();
      if (context.mounted) {
        final detail =
            describeUserFacingError(error, l10n: l10n).displayMessage;
        showOmniFeedback(
          context,
          '${l10n.photosSaveFailed}: $detail',
          severity: OmniFeedbackSeverity.error,
        );
      }
      rethrow;
    }
  }
}
