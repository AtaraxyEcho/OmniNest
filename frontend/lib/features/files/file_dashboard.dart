/// 文件模块提供给跨 Feature 仪表盘的只读契约。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/log/dev_log.dart';
import 'package:omninest/features/files/data/file_providers.dart'
    show fileRepositoryProvider;
import 'package:omninest/features/files/domain/file_node.dart' show FileNode;

export 'package:omninest/features/files/application/file_browser_controller.dart'
    show fileStorageStatsProvider;
export 'package:omninest/features/files/domain/file_manager_models.dart'
    show FileStorageStats;
export 'package:omninest/features/files/domain/file_node.dart' show FileNode;

/// 跨 Feature（全局搜索等）的文件预设：优先最近文件，为空时回退根目录。
final fileRecentEntriesProvider = FutureProvider<List<FileNode>>((ref) async {
  final repo = ref.watch(fileRepositoryProvider);
  try {
    final recent = await repo.listRecentFiles();
    if (recent.isNotEmpty) {
      return recent;
    }
  } on Exception catch (error) {
    devLog('最近文件加载失败，回退根目录: $error');
  }
  try {
    return await repo.listFiles();
  } on Exception catch (error) {
    devLog('根目录文件加载失败: $error');
    return const <FileNode>[];
  }
});
