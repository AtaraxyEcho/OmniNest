import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/storage/local_database_provider.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_preferences.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_api.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_bundled_asset.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_repository.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';

final appBackdropRepositoryProvider = Provider<AppBackdropRepository>((ref) {
  return AppBackdropRepository(ref.watch(localDatabaseProvider));
});

final appBackdropApiProvider = Provider<BackdropApi>((ref) {
  return BackdropApi(ref.watch(apiClientProvider));
});

final appBackdropBundledAssetInstallerProvider =
    Provider<AppBackdropBundledAssetInstaller>((ref) {
      return AppBackdropBundledAssetInstaller();
    });

final appBackdropSelectionTargetProvider = Provider<AppBackdropSelectionTarget>(
  (ref) =>
      isMobilePlatform
          ? AppBackdropSelectionTarget.mobile
          : AppBackdropSelectionTarget.desktop,
);

final appBackdropControllerProvider =
    AsyncNotifierProvider<AppBackdropController, AppBackdropState>(
      AppBackdropController.new,
    );

/// 应用背景库控制器。
///
/// 服务端素材库与用户偏好(scope=backdrop)是事实来源,drift 行为离线缓存与
/// 内置壁纸登记;本机文件导入链路已退役,素材统一经服务端流转。
class AppBackdropController extends AsyncNotifier<AppBackdropState> {
  @override
  Future<AppBackdropState> build() async {
    final repository = ref.watch(appBackdropRepositoryProvider);
    ref.watch(appBackdropSelectionTargetProvider);
    await _registerBundledBackdrop(repository);
    // 等待服务端设置落到本地镜像(离线时为缓存),再装配状态。
    await ref.watch(backdropPreferencesProvider.future);
    await refreshServerAssets();
    return _loadCurrentState(repository);
  }

  /// 拉取服务端素材并写入本地缓存;离线时保留缓存内容。
  Future<void> refreshServerAssets() async {
    final repository = ref.read(appBackdropRepositoryProvider);
    try {
      final assets = await ref.read(appBackdropApiProvider).list();
      await repository.upsertServerAssets(assets);
    } on Exception catch (error) {
      if (kDebugMode) {
        debugPrint('背景库服务端列表同步失败(可能离线): $error');
      }
    }
  }

  /// 选择背景素材;设置经由偏好同步(服务端事实来源)落盘。
  Future<void> selectBackdrop(String id) async {
    final current =
        state.asData?.value ??
        await _loadCurrentState(ref.read(appBackdropRepositoryProvider));
    final selected = current.backdrops.where((backdrop) => backdrop.id == id);
    if (selected.isEmpty) {
      return;
    }
    final updated = current.settings.selectBackdropFor(
      current.selectionTarget,
      id,
    );
    await _persistSettings(updated);
  }

  /// 设置桌面端和移动端是否分别保存背景选择。
  Future<void> setDeviceSeparation(bool separate) async {
    final current =
        state.asData?.value ??
        await _loadCurrentState(ref.read(appBackdropRepositoryProvider));
    final updated = current.settings.withDeviceSeparation(
      separate,
      current.selectionTarget,
    );
    await _persistSettings(updated);
  }

  /// 启用或关闭背景。
  Future<void> setEnabled(bool enabled) async {
    final current =
        state.asData?.value ??
        await _loadCurrentState(ref.read(appBackdropRepositoryProvider));
    final nextEnabled = enabled && current.selectedBackdrop != null;
    await _persistSettings(current.settings.copyWith(enabled: nextEnabled));
  }

  /// 更新背景适配方式。
  Future<void> setFit(AppBackdropFit fit) async {
    final current =
        state.asData?.value ??
        await _loadCurrentState(ref.read(appBackdropRepositoryProvider));
    await _persistSettings(current.settings.copyWith(fit: fit));
  }

  /// 更新背景暗化强度。
  Future<void> setDimAmount(double value) async {
    final current =
        state.asData?.value ??
        await _loadCurrentState(ref.read(appBackdropRepositoryProvider));
    await _persistSettings(current.settings.copyWith(dimAmount: value));
  }

  /// 更新背景模糊强度。
  Future<void> setBlurAmount(double value) async {
    final current =
        state.asData?.value ??
        await _loadCurrentState(ref.read(appBackdropRepositoryProvider));
    await _persistSettings(current.settings.copyWith(blurAmount: value));
  }

  /// 更新视频静音设置。
  Future<void> setVideoMuted(bool muted) async {
    final current =
        state.asData?.value ??
        await _loadCurrentState(ref.read(appBackdropRepositoryProvider));
    await _persistSettings(current.settings.copyWith(videoMuted: muted));
  }

  /// 移除背景素材;服务端素材先调删除接口,失败则保持本地现状。
  Future<void> removeBackdrop(String id) async {
    final current =
        state.asData?.value ??
        await _loadCurrentState(ref.read(appBackdropRepositoryProvider));
    final selected = current.backdrops.where((backdrop) => backdrop.id == id);
    if (selected.isEmpty) {
      return;
    }
    if (selected.any((backdrop) => backdrop.isBundled)) {
      return;
    }
    final isServer = selected.any(
      (backdrop) => backdrop.sourceType == AppBackdropSourceType.server,
    );
    if (isServer) {
      try {
        await ref.read(appBackdropApiProvider).delete(id);
      } on Exception catch (error) {
        if (kDebugMode) {
          debugPrint('背景素材删除失败,保留本地缓存: $error');
        }
        return;
      }
    }
    await ref.read(appBackdropRepositoryProvider).removeBackdrop(id);
    state = AsyncData(
      await _loadCurrentState(ref.read(appBackdropRepositoryProvider)),
    );
  }

  /// 清空本地背景库缓存;内置壁纸与选择保留。
  Future<void> clearBackdrops() async {
    await ref.read(appBackdropRepositoryProvider).clearBackdrops();
    state = AsyncData(
      await _loadCurrentState(ref.read(appBackdropRepositoryProvider)),
    );
  }

  Future<void> _registerBundledBackdrop(
    AppBackdropRepository repository,
  ) async {
    try {
      final bundledAsset =
          await ref.read(appBackdropBundledAssetInstallerProvider).install();
      if (bundledAsset != null) {
        await repository.ensureBundledBackdrop(bundledAsset);
      }
    } on Object catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('应用内置背景注册失败: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  Future<void> _persistSettings(AppBackdropSettings settings) async {
    await ref.read(backdropPreferencesProvider.notifier).save(settings);
    state = AsyncData(
      await _loadCurrentState(ref.read(appBackdropRepositoryProvider)),
    );
  }

  Future<AppBackdropState> _loadCurrentState(
    AppBackdropRepository repository,
  ) async {
    final loaded = await repository.loadState();
    return loaded.copyWith(
      selectionTarget: ref.read(appBackdropSelectionTargetProvider),
    );
  }
}
