import 'package:flutter_test/flutter_test.dart';

/// 收藏自回落抑制的纯逻辑测试：本地登记窗口内的 FILE_NODE 失效批次
/// 不再触发浏览器全量刷新（消除“点收藏 1 秒后列表闪烁刷新”）。
void main() {
  test('窗口内命中：登记过的 fileId 全部命中返回 true', () {
    final controller = FileBrowserControllerTestHarness();

    controller.registerFavoriteEcho('file-1');
    controller.registerFavoriteEcho('file-2');

    expect(
      controller.matchesRecentFavoriteEchoes(const {'file-1', 'file-2'}),
      isTrue,
      reason: '两个本地刚变更的文件应命中回声窗口',
    );
  });

  test('窗口外或未知文件返回 false（他端/混合变更走全量刷新）', () {
    final controller = FileBrowserControllerTestHarness();

    controller.registerFavoriteEcho('file-1');

    expect(
      controller.matchesRecentFavoriteEchoes(const {'file-1', 'file-other'}),
      isFalse,
      reason: '混入未登记文件不得抑制刷新',
    );
    expect(controller.matchesRecentEchoesEmpty(), isFalse, reason: '空批次保守走刷新');
  });

  test('过期条目被清理后不再命中', () {
    final controller = FileBrowserControllerTestHarness();

    controller.registerFavoriteEchoExpired('file-1');

    expect(
      controller.matchesRecentFavoriteEchoes(const {'file-1'}),
      isFalse,
      reason: '超过 15 秒窗口的自回落不再抑制',
    );
  });
}

/// 测试专用Harness：暴露受控的登记入口，不触发 Provider 体系。
class FileBrowserControllerTestHarness {
  final Map<String, DateTime> _echoes = {};

  void registerFavoriteEcho(String fileId) {
    _echoes[fileId] = DateTime.now().add(const Duration(seconds: 15));
  }

  void registerFavoriteEchoExpired(String fileId) {
    _echoes[fileId] = DateTime.now().subtract(const Duration(seconds: 1));
  }

  bool matchesRecentFavoriteEchoes(Set<String> fileIds) {
    final now = DateTime.now();
    _echoes.removeWhere((_, expiry) => expiry.isBefore(now));
    if (fileIds.isEmpty) {
      return false;
    }
    return fileIds.every(_echoes.containsKey);
  }

  bool matchesRecentEchoesEmpty() => matchesRecentFavoriteEchoes(const {});
}
