import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/public_share.dart';

/// 定向分享文件夹的浏览态。
class SharedFolderBrowse {
  const SharedFolderBrowse({required this.trail, required this.page});

  /// 已进入的目录，末元素为当前目录；空表示停在分享根目录。
  final List<ShareChild> trail;
  final FilesSubPage<ShareChild> page;

  ShareChild? get current => trail.isEmpty ? null : trail.last;
}

/// 接收人浏览定向分享文件夹的状态：目录栈与分页都由应用层持有，
/// 展示层只发起动作和渲染结果。
final sharedFolderBrowseProvider = AsyncNotifierProvider.autoDispose<
  SharedFolderBrowseNotifier,
  SharedFolderBrowse?
>(SharedFolderBrowseNotifier.new);

class SharedFolderBrowseNotifier extends AsyncNotifier<SharedFolderBrowse?> {
  String _shareId = '';
  int _generation = 0;

  @override
  SharedFolderBrowse? build() => null;

  /// 打开某条分享的根目录。
  Future<void> open(String shareId) async {
    _shareId = shareId;
    await _load(const []);
  }

  /// 进入子目录。
  Future<void> descend(ShareChild folder) async {
    final current = state.asData?.value;
    await _load([...?current?.trail, folder]);
  }

  /// 返回上一级；已在根目录时不动作。
  Future<void> ascend() async {
    final current = state.asData?.value;
    if (current == null || current.trail.isEmpty) {
      return;
    }
    await _load(current.trail.sublist(0, current.trail.length - 1));
  }

  /// 重试当前目录。
  Future<void> retry() async {
    await _load(state.asData?.value?.trail ?? const []);
  }

  Future<void> _load(List<ShareChild> trail) async {
    // 快速连点或返回后旧响应回写会让列表停在错误目录，按代次丢弃过期结果。
    final generation = ++_generation;
    state = const AsyncLoading();
    try {
      final page = await ref
          .read(fileRepositoryProvider)
          .listSharedFolderChildren(
            shareId: _shareId,
            parentId: trail.isEmpty ? null : trail.last.id,
          );
      if (generation != _generation) {
        return;
      }
      state = AsyncData(SharedFolderBrowse(trail: trail, page: page));
    } on Object catch (error, stackTrace) {
      if (generation != _generation) {
        return;
      }
      state = AsyncError(error, stackTrace);
    }
  }
}
