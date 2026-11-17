import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/files/data/file_providers.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';

/// 文件媒体元数据探测（视频时长/分辨率）；失败静默为 null。
final fileMediaInfoProvider = FutureProvider.autoDispose
    .family<FileMediaInfo?, String>((ref, fileId) async {
      try {
        return await ref.watch(fileRepositoryProvider).mediaInfo(fileId);
      } on Object {
        return null;
      }
    });
