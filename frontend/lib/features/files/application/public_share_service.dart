import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/features/files/data/share_api.dart';
import 'package:omninest/features/files/domain/public_share.dart';

/// 公开分享页面使用的应用服务。
class PublicShareService {
  PublicShareService(this._repository);

  final PublicShareRepository _repository;

  /// 登录回跳后仍需完成的转存标记；只保存在内存，随服务实例跨页面存活。
  final Set<String> _pendingAccepts = <String>{};

  /// 标记登录成功后需要自动完成的转存。
  void markPendingAccept(String token) {
    _pendingAccepts.add(token);
  }

  /// 读取并清除待转存标记。
  bool takePendingAccept(String token) {
    return _pendingAccepts.remove(token);
  }

  Future<SharePreviewResult> preview(String token, {String? password}) {
    return _repository.preview(token, password: password);
  }

  Future<ShareChildrenResult> listChildren(
    String token, {
    String? parentId,
    int page = 0,
    int size = 50,
  }) {
    return _repository.listChildren(
      token,
      parentId: parentId,
      page: page,
      size: size,
    );
  }

  Future<ShareAcceptResult> accept(
    String token, {
    String? password,
    String? authToken,
    String? targetParentId,
  }) {
    return _repository.accept(
      token,
      password: password,
      authToken: authToken,
      targetParentId: targetParentId,
    );
  }

  /// 匿名获取单文件的短期下载地址。
  Future<ShareAccessResult> access(String token, {String? password}) {
    return _repository.access(token, password: password);
  }
}

/// 公开分享应用服务依赖注入入口。
final publicShareServiceProvider = Provider<PublicShareService>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  if (environment == null) {
    throw StateError('服务器地址未配置');
  }
  final api = ShareApi(
    environment.apiBaseUrl,
    authDio: ref.watch(apiClientProvider).dio,
  );
  ref.onDispose(api.close);
  return PublicShareService(api);
});
