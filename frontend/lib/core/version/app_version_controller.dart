import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/version/app_version_api.dart';

/// 版本检查的应用层入口。
final appVersionControllerProvider = Provider<AppVersionController>((ref) {
  return AppVersionController(ref.watch(appVersionApiProvider));
});

/// 检查是否发布了新版本。
///
/// 版本比较与“不高于当前安装版本不算新版本”的判据留在数据层，这里只作为
/// presentation 的调用点，避免页面直接持有 API 对象。
class AppVersionController {
  const AppVersionController(this._api);

  final AppVersionApi _api;

  Future<AppVersionInfo?> checkForUpdate() => _api.version();
}
