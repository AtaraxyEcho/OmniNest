import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/storage/local_database_provider.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_preferences.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_api.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_bundled_asset.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_file_picker.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_repository.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';

final appBackdropRepositoryProvider = Provider<AppBackdropRepository>((ref) {
  return AppBackdropRepository(ref.watch(localDatabaseProvider));
});

final appBackdropApiProvider = Provider<BackdropApi>((ref) {
  return BackdropApi(ref.watch(apiClientProvider));
});

final appBackdropFilePickerProvider = Provider<BackdropFilePicker>((ref) {
  return const DefaultBackdropFilePicker();
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

/// 需要映射专属文案、不自动重试的业务错误码。
const _nonTransientUploadCodes = {
  '8002',
  '8003',
  '8004',
  '8005',
  '8006',
  '8007',
  '429',
};

final appBackdropControllerProvider =
    AsyncNotifierProvider<AppBackdropController, AppBackdropState>(
      AppBackdropController.new,
    );

/// 应用背景库控制器。
///
/// 服务端素材库与用户偏好(scope=backdrop)是事实来源,drift 行为离线缓存与
/// 内置壁纸登记;本机文件导入链路已退役,素材统一经服务端流转。
class AppBackdropController extends AsyncNotifier<AppBackdropState> {
  /// 签名 URL 过期时间(内存态,避免为过期检测扩大 drift schema)。
  final Map<String, DateTime> _urlExpiresAt = <String, DateTime>{};

  static const Duration _urlRefreshLead = Duration(minutes: 2);
  Future<void>? _settingsMutation;

  @override
  Future<AppBackdropState> build() async {
    final repository = ref.watch(appBackdropRepositoryProvider);
    ref.watch(appBackdropSelectionTargetProvider);
    final session = await ref.watch(authSessionProvider.future);
    final userId = session.user?.id;
    await _registerBundledBackdrop(repository);
    // read 而非 watch:偏好 save 会更新 state,若 watch(future) 会导致本控制器
    // 在每次选中/启用后整树重建 → 反复 refresh → 视频会话被打断。
    await ref.read(backdropPreferencesProvider.future);
    if (userId != null) {
      await refreshServerAssets();
    }
    var loaded = await _loadCurrentState(repository);
    if (!loaded.hasActiveBackdrop) {
      AppBackdropAsset? bundled;
      for (final backdrop in loaded.backdrops) {
        if (backdrop.isBundled && backdrop.isSelectable) {
          bundled = backdrop;
          break;
        }
      }
      if (bundled != null) {
        final selectedId = loaded.settings.selectedBackdropId;
        AppBackdropAsset? selected;
        if (selectedId != null) {
          for (final backdrop in loaded.backdrops) {
            if (backdrop.id == selectedId) {
              selected = backdrop;
              break;
            }
          }
        }
        final needBundledFallback = selected == null || !selected.isSelectable;
        // 选中了内置壁纸但被关闭时,保持用户关闭意图;
        // 无选中或选中不可用时,回落内置壁纸并启用,保证启动即有背景。
        if (needBundledFallback) {
          final next = loaded.settings.copyWith(
            enabled: true,
            selectedBackdropId: bundled.id,
            desktopBackdropId:
                loaded.settings.separateDeviceBackdrops
                    ? bundled.id
                    : loaded.settings.desktopBackdropId,
            mobileBackdropId:
                loaded.settings.separateDeviceBackdrops
                    ? bundled.id
                    : loaded.settings.mobileBackdropId,
          );
          await repository.saveSettings(next);
          loaded = await _loadCurrentState(repository);
          }
      } else {
        }
    }
    return loaded;
  }

  /// 拉取服务端素材并写入本地缓存;未登录(如安装引导阶段)与离线时保留缓存内容。
  Future<void> refreshServerAssets() async {
    final session = await ref.read(authSessionProvider.future);
    if (!session.isAuthenticated) {
      return;
    }
    final repository = ref.read(appBackdropRepositoryProvider);
    try {
      final assets = await ref.read(appBackdropApiProvider).list();
      for (final asset in assets) {
        final expiresAt = asset.contentUrlExpiresAt;
        if (expiresAt != null) {
          _urlExpiresAt[asset.id] = expiresAt;
        } else {
          _urlExpiresAt.remove(asset.id);
        }
      }
      await repository.upsertServerAssets(assets);
    } on Exception catch (error) {
      if (kDebugMode) {
        debugPrint('背景库服务端列表同步失败(可能离线): $error');
      }
    }
  }

  /// 签名 URL 可能已过期或即将过期时刷新服务端列表。
  ///
  /// [force] 为 true 时无条件刷新(如视频打开失败后的补偿)。
  Future<void> ensureFreshServerUrls({bool force = false}) async {
    final session = await ref.read(authSessionProvider.future);
    if (!session.isAuthenticated) {
      return;
    }
    if (!force && !_serverUrlsNeedRefresh()) {
      return;
    }
    await refreshServerAssets();
    final refreshed = await _loadCurrentState(
      ref.read(appBackdropRepositoryProvider),
    );
    state = AsyncData(refreshed);
  }

  bool _serverUrlsNeedRefresh() {
    final current = state.asData?.value;
    final hasServerAssets =
        current?.backdrops.any(
          (backdrop) => backdrop.sourceType == AppBackdropSourceType.server,
        ) ??
        false;
    if (!hasServerAssets && _urlExpiresAt.isEmpty) {
      // 仅内置壁纸或空库,无需刷新签名 URL。
      return false;
    }
    if (_urlExpiresAt.isEmpty) {
      // 本地有服务端缓存但内存无过期信息(冷启动),视为需要刷新。
      return true;
    }
    final threshold = DateTime.now().add(_urlRefreshLead);
    return _urlExpiresAt.values.any(
      (expiresAt) => !expiresAt.isAfter(threshold),
    );
  }

  /// 唤起文件选择并逐个上传。
  /// 网络类失败自动重试一次;全部结束后刷新列表并记录失败条目。
  Future<void> addBackdropFiles() async {
    final session = await ref.read(authSessionProvider.future);
    if (!session.isAuthenticated) {
      return;
    }
    final current = state.asData?.value;
    if (current?.uploading == true) {
      return;
    }
    final picked = await ref.read(appBackdropFilePickerProvider).pick();
    if (picked.isEmpty) {
      return;
    }
    state = AsyncData(
      (current ??
              await _loadCurrentState(ref.read(appBackdropRepositoryProvider)))
          .copyWith(uploading: true, clearUploadFailures: true),
    );
    final failures = <BackdropUploadFailure>[];
    for (final file in picked) {
      try {
        final asset = await _uploadWithRetry(file);
        await ref.read(appBackdropRepositoryProvider).upsertServerAssets([
          asset,
        ]);
      } on AppException catch (error) {
        if (kDebugMode) {
          debugPrint('背景素材上传失败: ${file.name} code=${error.code}');
        }
        failures.add(BackdropUploadFailure(title: file.name, code: error.code));
      } on Exception catch (error) {
        if (kDebugMode) {
          debugPrint('背景素材上传异常: ${file.name} $error');
        }
        failures.add(BackdropUploadFailure(title: file.name, code: 'UNKNOWN'));
      }
    }
    await refreshServerAssets();
    final refreshed = await _loadCurrentState(
      ref.read(appBackdropRepositoryProvider),
    );
    state = AsyncData(
      refreshed.copyWith(uploading: false, failedUploads: failures),
    );
  }

  Future<BackdropServerAsset> _uploadWithRetry(BackdropPickedFile file) async {
    try {
      return await ref.read(appBackdropApiProvider).upload(file);
    } on AppException catch (error) {
      if (_nonTransientUploadCodes.contains(error.code)) {
        rethrow;
      }
      // 网络类失败自动重试一次。
      return await ref.read(appBackdropApiProvider).upload(file);
    }
  }

  /// 选择背景素材;设置经由偏好同步(服务端事实来源)落盘。
  /// 首次选中时若背景未启用,自动打开;先写本地镜像再同步,避免冲突导致白屏。
  Future<void> selectBackdrop(String id) async {
    var current =
        state.asData?.value ??
        await _loadCurrentState(ref.read(appBackdropRepositoryProvider));
    var selected = current.backdrops.where((backdrop) => backdrop.id == id);
    if (selected.isEmpty || !selected.single.isSelectable) {
      await ensureFreshServerUrls(force: true);
      current =
          state.asData?.value ??
          await _loadCurrentState(ref.read(appBackdropRepositoryProvider));
      selected = current.backdrops.where((b) => b.id == id);
      if (selected.isEmpty || !selected.single.isSelectable) {
        return;
      }
    }
    var updated = current.settings.selectBackdropFor(
      current.selectionTarget,
      id,
    );
    if (!updated.enabled) {
      updated = updated.copyWith(enabled: true);
    }
    // 非设备分离时同步三槽位,避免 desktop/mobile 残留旧 ID 导致归一化来回切。
    if (!updated.separateDeviceBackdrops) {
      updated = updated.copyWith(
        selectedBackdropId: id,
        desktopBackdropId: id,
        mobileBackdropId: id,
      );
    }
    await _applySettings(updated);
    final after =
        state.asData?.value ??
        await _loadCurrentState(ref.read(appBackdropRepositoryProvider));
    if (after.settings.selectedBackdropId != id ||
        !after.hasActiveBackdrop) {
      await _applySettings(updated);
    }
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

  /// 更新 cover/fill 对齐锚点。
  Future<void> setAlignment(AppBackdropAlignment alignment) async {
    final current =
        state.asData?.value ??
        await _loadCurrentState(ref.read(appBackdropRepositoryProvider));
    await _persistSettings(current.settings.copyWith(alignment: alignment));
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
        final failed = await _loadCurrentState(
          ref.read(appBackdropRepositoryProvider),
        );
        state = AsyncData(
          failed.copyWith(message: AppBackdropMessage.deleteFailed),
        );
        return;
      }
      _urlExpiresAt.remove(id);
    }
    await ref.read(appBackdropRepositoryProvider).removeBackdrop(id);
    state = AsyncData(
      await _loadCurrentState(ref.read(appBackdropRepositoryProvider)),
    );
  }

  /// 清空服务端背景素材库并同步清理本地缓存;内置壁纸与选择保留。
  /// 部分失败时仍清理已成功条目,并在状态中记录 removed/failed。
  Future<void> clearBackdrops() async {
    final session = await ref.read(authSessionProvider.future);
    var removed = 0;
    var failed = 0;
    if (session.isAuthenticated) {
      try {
        final result = await ref.read(appBackdropApiProvider).deleteAll();
        removed = result.deleted;
        failed = result.failed;
        if (failed == 0) {
          _urlExpiresAt.clear();
        } else {
          await refreshServerAssets();
        }
      } on Exception catch (error) {
        if (kDebugMode) {
          debugPrint('背景库服务端清空失败,保留本地现状: $error');
        }
        final current = await _loadCurrentState(
          ref.read(appBackdropRepositoryProvider),
        );
        state = AsyncData(
          current.copyWith(message: AppBackdropMessage.deleteFailed),
        );
        return;
      }
    }
    await ref.read(appBackdropRepositoryProvider).clearBackdrops();
    final refreshed = await _loadCurrentState(
      ref.read(appBackdropRepositoryProvider),
    );
    state = AsyncData(
      refreshed.copyWith(
        clearResult: BackdropClearResult(removed: removed, failed: failed),
        message: failed > 0 ? AppBackdropMessage.deleteFailed : null,
      ),
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

  Future<void> _persistSettings(AppBackdropSettings settings) {
    return _applySettings(settings);
  }

  /// 串行写设置:先本地镜像即时生效,再同步服务端,最后回读状态。
  Future<void> _applySettings(AppBackdropSettings settings) {
    final previous = _settingsMutation ?? Future<void>.value();
    final next = previous.then((_) => _applySettingsUnlocked(settings));
    _settingsMutation = next.catchError((Object _) {});
    return next;
  }

  Future<void> _applySettingsUnlocked(AppBackdropSettings settings) async {
    await ref.read(appBackdropRepositoryProvider).saveSettings(settings);
    state = AsyncData(
      await _loadCurrentState(ref.read(appBackdropRepositoryProvider)),
    );
    final prefs = ref.read(backdropPreferencesProvider).asData?.value;
    if (prefs == settings) {
      return;
    }
    await ref.read(backdropPreferencesProvider.notifier).save(settings);
    final after = await _loadCurrentState(
      ref.read(appBackdropRepositoryProvider),
    );
    if (state.asData?.value != after) {
      state = AsyncData(after);
    }
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
