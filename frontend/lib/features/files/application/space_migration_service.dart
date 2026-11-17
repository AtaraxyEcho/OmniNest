import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/files/data/file_api.dart';
import 'package:omninest/features/files/data/file_providers.dart';

/// 文件节点在个人空间与共享空间之间迁移。
///
/// 供 Reader 等业务模块通过 application 层调用，不直接触达 data 层。
class SpaceMigrationService {
  const SpaceMigrationService(this._fileApi);

  final FileApi _fileApi;

  /// 将文件节点迁移到共享空间。
  Future<void> moveToSharedSpace(String fileNodeId) {
    return _fileApi.moveToSharedSpace(fileNodeId);
  }

  /// 将文件节点迁回个人空间。
  Future<void> moveToPersonalSpace(String fileNodeId) {
    return _fileApi.moveToPersonalSpace(fileNodeId);
  }
}

final spaceMigrationServiceProvider = Provider<SpaceMigrationService>((ref) {
  return SpaceMigrationService(ref.watch(fileApiProvider));
});
