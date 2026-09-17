import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';

/// 会话内复用 presigned download URL。
///
/// 使用 keepAlive + TTL，避免列表滚动导致 tile 销毁后立刻失效并重复签 URL。
final fileDownloadUrlProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, fileId) async {
      final link = ref.keepAlive();
      final timer = Timer(const Duration(minutes: 10), link.close);
      ref.onDispose(timer.cancel);
      final repository = ref.read(fileRepositoryProvider);
      try {
        return await repository.downloadUrl(fileId);
      } catch (_) {
        return null;
      }
    });

/// 按文件 ID 加载有界文本预览。
final fileTextPreviewProvider = FutureProvider.autoDispose
    .family<String, String>((ref, fileId) async {
      final link = ref.keepAlive();
      final timer = Timer(const Duration(minutes: 5), link.close);
      ref.onDispose(timer.cancel);
      return ref.read(fileRepositoryProvider).loadTextPreview(fileId);
    });
