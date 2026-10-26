import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/files/data/file_providers.dart';
import 'package:omninest/features/files/domain/file_node.dart';

/// 单个文件节点；搜索结果跳转预览时按 ID 拉取完整节点。
final fileNodeByIdProvider = FutureProvider.autoDispose.family<FileNode, String>(
  (ref, fileId) => ref.watch(fileApiProvider).getFileNode(fileId),
);
