import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';

final shareLinkControllerProvider =
    AsyncNotifierProvider.autoDispose<ShareLinkController, FileShareLink?>(
      ShareLinkController.new,
    );

/// 我的分享链接列表状态。
final myShareLinksProvider = AsyncNotifierProvider.autoDispose<
  MyShareLinksNotifier,
  List<FileShareLink>
>(MyShareLinksNotifier.new);

class ShareLinkController extends AsyncNotifier<FileShareLink?> {
  @override
  FileShareLink? build() => null;

  /// 创建分享链接并存储到 state。
  Future<FileShareLink> createShareLink({
    required String resourceId,
    required String resourceType,
    String? password,
    bool generatePassword = false,
    DateTime? expiresAt,
    int? maxAccessCount,
  }) async {
    state = const AsyncLoading();
    final repository = ref.read(fileRepositoryProvider);
    final link = await repository.createShareLink(
      resourceId: resourceId,
      resourceType: resourceType,
      password: password,
      generatePassword: generatePassword,
      expiresAt: expiresAt,
      maxAccessCount: maxAccessCount,
    );
    state = AsyncData(link);
    await _refreshShareLists();
    return link;
  }

  /// 撤销分享链接。
  Future<void> revokeShare(String shareId) async {
    final repository = ref.read(fileRepositoryProvider);
    await repository.revokeShare(shareId);
    state = const AsyncData(null);
    await _refreshShareLists();
  }

  /// 定向刷新分享相关列表，避免重建整个文件浏览器 Controller。
  Future<void> _refreshShareLists() async {
    if (ref.exists(myShareLinksProvider)) {
      await ref.read(myShareLinksProvider.notifier).load();
    }
    if (!ref.exists(fileBrowserControllerProvider)) {
      return;
    }
    final browser = ref.read(fileBrowserControllerProvider.notifier);
    final section =
        ref.read(fileBrowserControllerProvider).asData?.value.section;
    switch (section) {
      case FileManagerSection.myShares:
        await browser.showMyShares();
      case FileManagerSection.shareManagement:
        await browser.showShareLinks();
      default:
        break;
    }
  }

  /// 重置状态（弹窗关闭时调用）。
  void reset() {
    state = const AsyncData(null);
  }
}

class MyShareLinksNotifier extends AsyncNotifier<List<FileShareLink>> {
  @override
  List<FileShareLink> build() => [];

  /// 加载我的分享链接列表。
  Future<void> load() async {
    state = const AsyncLoading();
    final repository = ref.read(fileRepositoryProvider);
    final links = await repository.listMyShares();
    state = AsyncData(links);
  }

  /// 撤销分享链接并刷新列表。
  Future<void> revokeShare(String shareId) async {
    final repository = ref.read(fileRepositoryProvider);
    await repository.revokeShare(shareId);
    await load();
    if (!ref.exists(fileBrowserControllerProvider)) {
      return;
    }
    final browser = ref.read(fileBrowserControllerProvider.notifier);
    final section =
        ref.read(fileBrowserControllerProvider).asData?.value.section;
    switch (section) {
      case FileManagerSection.myShares:
        await browser.showMyShares();
      case FileManagerSection.shareManagement:
        await browser.showShareLinks();
      default:
        break;
    }
  }
}
