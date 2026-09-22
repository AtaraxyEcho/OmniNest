import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_api.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_repository.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_settings_json.dart';

void main() {
  // Repository 组用 rootBundle 校验打包资产，需要初始化测试 binding。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppBackdropState', () {
    final first = AppBackdropAsset(
      id: 'first',
      path: '',
      title: 'first',
      mediaType: AppBackdropMediaType.image,
      sourceType: AppBackdropSourceType.server,
      fileSize: 1024,
      modifiedAt: DateTime(2026),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final second = first.copyWith(
      id: 'second',
      mediaType: AppBackdropMediaType.video,
    );

    test('没有显式选择时不返回背景', () {
      final state = AppBackdropState(backdrops: [first, second]);

      expect(state.selectedBackdrop, isNull);
    });

    test('显式选择存在时优先使用对应背景', () {
      final state = AppBackdropState(
        backdrops: [first, second],
        settings: const AppBackdropSettings(selectedBackdropId: 'second'),
      );

      expect(state.selectedBackdrop, second);
    });

    test('显式选择不存在时不返回背景', () {
      final state = AppBackdropState(
        backdrops: [first, second],
        settings: const AppBackdropSettings(selectedBackdropId: 'missing'),
      );

      expect(state.selectedBackdrop, isNull);
    });

    test('空素材库不返回背景', () {
      const state = AppBackdropState();

      expect(state.selectedBackdrop, isNull);
      expect(state.hasActiveBackdrop, isFalse);
    });

    test('仅在素材存在且显式启用时返回活动状态', () {
      final disabled = AppBackdropState(
        backdrops: [first],
        settings: const AppBackdropSettings(selectedBackdropId: 'first'),
      );
      final enabled = AppBackdropState(
        backdrops: [first],
        settings: const AppBackdropSettings(
          enabled: true,
          selectedBackdropId: 'first',
        ),
      );

      expect(disabled.hasActiveBackdrop, isFalse);
      expect(enabled.hasActiveBackdrop, isTrue);
    });

    test('隔离开启后按设备类别返回对应背景', () {
      final settings = const AppBackdropSettings(
        enabled: true,
        separateDeviceBackdrops: true,
        desktopBackdropId: 'first',
        mobileBackdropId: 'second',
      );
      final desktop = AppBackdropState(
        backdrops: [first, second],
        settings: settings,
      );
      final mobile = desktop.copyWith(
        selectionTarget: AppBackdropSelectionTarget.mobile,
      );

      expect(desktop.selectedBackdrop, first);
      expect(mobile.selectedBackdrop, second);
      expect(desktop.hasActiveBackdrop, isTrue);
      expect(mobile.hasActiveBackdrop, isTrue);
    });

    test('PROCESSING/FAILED 素材不可作为活动背景', () {
      final processing = first.copyWith(id: 'processing', missing: true);
      final state = AppBackdropState(
        backdrops: [processing],
        settings: const AppBackdropSettings(
          enabled: true,
          selectedBackdropId: 'processing',
        ),
      );

      expect(state.selectedBackdrop?.missing, isTrue);
      expect(state.hasActiveBackdrop, isFalse);
    });
  });

  group('AppBackdropSettings', () {
    test('fit 支持 cover/contain/fill,alignment 默认 center', () {
      const settings = AppBackdropSettings();

      expect(settings.fit, AppBackdropFit.cover);
      expect(settings.alignment, AppBackdropAlignment.center);
      expect(AppBackdropFit.fromValue('fill'), AppBackdropFit.fill);
      expect(AppBackdropAlignment.fromValue('top'), AppBackdropAlignment.top);
      expect(
        AppBackdropAlignment.fromValue('unknown'),
        AppBackdropAlignment.center,
      );
    });

    test('开启隔离时从共享选择初始化两端槽位', () {
      const settings = AppBackdropSettings(selectedBackdropId: 'shared');

      final separated = settings.withDeviceSeparation(
        true,
        AppBackdropSelectionTarget.desktop,
      );

      expect(separated.separateDeviceBackdrops, isTrue);
      expect(separated.desktopBackdropId, 'shared');
      expect(separated.mobileBackdropId, 'shared');
    });

    test('关闭后再次开启隔离会保留两端历史选择', () {
      const settings = AppBackdropSettings(
        selectedBackdropId: 'shared',
        separateDeviceBackdrops: true,
        desktopBackdropId: 'desktop',
        mobileBackdropId: 'mobile',
      );

      final shared = settings.withDeviceSeparation(
        false,
        AppBackdropSelectionTarget.desktop,
      );
      final restored = shared.withDeviceSeparation(
        true,
        AppBackdropSelectionTarget.desktop,
      );

      expect(shared.selectedBackdropId, 'desktop');
      expect(restored.desktopBackdropId, 'desktop');
      expect(restored.mobileBackdropId, 'mobile');
    });

    test('相同字段的设置相等', () {
      const settings = AppBackdropSettings(
        enabled: true,
        selectedBackdropId: 'a',
      );

      expect(
        settings,
        const AppBackdropSettings(enabled: true, selectedBackdropId: 'a'),
      );
      expect(
        settings,
        isNot(
          const AppBackdropSettings(enabled: true, selectedBackdropId: 'b'),
        ),
      );
    });
  });

  group('AppBackdropSettingsJson', () {
    test('缺失键回落到当前设置', () {
      const fallback = AppBackdropSettings(
        enabled: true,
        selectedBackdropId: 'kept',
        dimAmount: 0.2,
      );

      final settings = AppBackdropSettingsJson.fromPreferences(
        const {},
        fallback,
      );

      expect(settings.enabled, isTrue);
      expect(settings.selectedBackdropId, 'kept');
      expect(settings.dimAmount, 0.2);
    });

    test('服务端键覆盖当前值且空选择映射为 null', () {
      const fallback = AppBackdropSettings(enabled: false);

      final settings = AppBackdropSettingsJson.fromPreferences(const {
        'enabled': true,
        'selectedAssetId': 'server-1',
        'separateDeviceBackdrops': true,
        'desktopAssetId': 'server-1',
        'mobileAssetId': null,
        'fit': 'contain',
        'dimAmount': 0.3,
        'blurAmount': 4.0,
        'videoMuted': false,
      }, fallback);

      expect(settings.enabled, isTrue);
      expect(settings.selectedBackdropId, 'server-1');
      expect(settings.separateDeviceBackdrops, isTrue);
      expect(settings.desktopBackdropId, 'server-1');
      expect(settings.mobileBackdropId, isNull);
      expect(settings.fit, AppBackdropFit.contain);
      expect(settings.dimAmount, 0.3);
      expect(settings.blurAmount, 4.0);
      expect(settings.videoMuted, isFalse);
    });

    test('toChanges 输出全量键值', () {
      const settings = AppBackdropSettings(
        enabled: true,
        selectedBackdropId: bundledDefaultWallpaperId,
      );

      final changes = AppBackdropSettingsJson.toChanges(settings);

      expect(changes['enabled'], isTrue);
      expect(changes['selectedAssetId'], bundledDefaultWallpaperId);
      expect(changes['fit'], 'cover');
      expect(changes['videoMuted'], isTrue);
      expect(
        changes.keys,
        containsAll(['separateDeviceBackdrops', 'dimAmount', 'blurAmount']),
      );
    });
  });

  group('AppBackdropRepository', () {
    test('默认壁纸已按设备档位打包进 Flutter 资源', () async {
      final desktop = await rootBundle.load(bundledDesktopWallpaperAssetPath);
      final mobile = await rootBundle.load(bundledMobileWallpaperAssetPath);

      expect(desktop.lengthInBytes, greaterThan(100 * 1024));
      expect(mobile.lengthInBytes, greaterThan(100 * 1024));
    });

    test('首次安装内置壁纸时默认启用且后续安装不覆盖用户设置', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      addTearDown(database.close);
      final bundled = AppBackdropAsset(
        id: bundledDefaultWallpaperId,
        path: 'D:/App/backdrops/default.mp4',
        title: 'OmniNest',
        mediaType: AppBackdropMediaType.video,
        sourceType: AppBackdropSourceType.bundled,
        fileSize: 5950165,
        modifiedAt: DateTime(2026),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      await repository.ensureBundledBackdrop(bundled);
      final initial = await repository.loadState();

      expect(initial.settings.enabled, isTrue);
      expect(initial.selectedBackdrop?.id, bundled.id);

      final custom = _backdrop('custom');
      await repository.upsertBackdrops([custom]);

      await repository.saveSettings(
        const AppBackdropSettings(enabled: false, selectedBackdropId: 'custom'),
      );
      await repository.ensureBundledBackdrop(bundled);
      final preserved = await repository.loadState();

      expect(preserved.settings.enabled, isFalse);
      expect(preserved.settings.selectedBackdropId, custom.id);
    });

    test('删除和清空操作保留内置壁纸', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      addTearDown(database.close);
      final bundled = AppBackdropAsset(
        id: bundledDefaultWallpaperId,
        path: 'D:/App/backdrops/default.mp4',
        title: 'OmniNest',
        mediaType: AppBackdropMediaType.video,
        sourceType: AppBackdropSourceType.bundled,
        fileSize: 5950165,
        modifiedAt: DateTime(2026),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final custom = _backdrop('custom');
      await repository.ensureBundledBackdrop(bundled);
      await repository.upsertBackdrops([custom]);

      await repository.removeBackdrop(bundled.id);
      expect((await repository.loadState()).backdrops, hasLength(2));

      await repository.clearBackdrops();
      final cleared = await repository.loadState();
      expect(cleared.backdrops, hasLength(1));
      expect(cleared.backdrops.single.id, bundled.id);
      expect(cleared.settings.selectedBackdropId, bundled.id);
    });

    test('注册新内置壁纸时清理旧版本行,多行内置不阻断清空', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      addTearDown(database.close);
      AppBackdropAsset bundledAsset(String id) => AppBackdropAsset(
        id: id,
        path: bundledDesktopWallpaperAssetPath,
        title: 'OmniNest',
        mediaType: AppBackdropMediaType.image,
        sourceType: AppBackdropSourceType.bundled,
        fileSize: 0,
        modifiedAt: DateTime(2026),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      // 模拟升级库:v1 旧内置行仍在,注册 v2 后应只剩 v2 一行。
      await repository.upsertBackdrops([
        bundledAsset('bundled-default-wallpaper-v1'),
        bundledAsset(bundledDefaultWallpaperId),
        _backdrop('custom'),
      ]);
      await repository.saveSettings(
        const AppBackdropSettings(enabled: true, selectedBackdropId: 'custom'),
      );

      await repository.ensureBundledBackdrop(
        bundledAsset(bundledDefaultWallpaperId),
      );
      final state = await repository.loadState();
      final bundledIds = state.backdrops
          .where(
            (backdrop) => backdrop.sourceType == AppBackdropSourceType.bundled,
          )
          .map((backdrop) => backdrop.id)
          .toList(growable: false);
      expect(bundledIds, [bundledDefaultWallpaperId]);

      // 即使防御式路径下出现多行内置(如清理未跑),clearBackdrops 也不得抛
      // "Too many elements",并把选择回落到内置素材。
      await repository.upsertBackdrops([
        bundledAsset('bundled-default-wallpaper-v1'),
      ]);
      await repository.clearBackdrops();
      final cleared = await repository.loadState();
      expect(cleared.backdrops, isNotEmpty);
      expect(
        cleared.backdrops.any(
          (backdrop) => backdrop.id == bundledDefaultWallpaperId,
        ),
        isTrue,
      );
      expect(
        cleared.settings.selectedBackdropId,
        anyOf(bundledDefaultWallpaperId, 'bundled-default-wallpaper-v1'),
      );
    });

    test('服务端素材写入缓存且非 READY 状态不可选', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      addTearDown(database.close);
      final ready = BackdropServerAsset(
        id: 'server-ready',
        title: 'ready',
        mediaType: 'image',
        status: 'READY',
        fileSize: 2048,
        updatedAt: DateTime(2026),
      );
      final processing = BackdropServerAsset(
        id: 'server-processing',
        title: 'processing',
        mediaType: 'image',
        status: 'PROCESSING',
        fileSize: 2048,
        updatedAt: DateTime(2026),
      );

      await repository.upsertServerAssets([ready, processing]);
      final state = await repository.loadState();

      final cached = state.backdrops.where(
        (backdrop) => backdrop.sourceType == AppBackdropSourceType.server,
      );
      expect(cached, hasLength(2));
      expect(
        state.backdrops
            .firstWhere((backdrop) => backdrop.id == 'server-ready')
            .missing,
        isFalse,
      );
      expect(
        state.backdrops
            .firstWhere((backdrop) => backdrop.id == 'server-processing')
            .missing,
        isTrue,
      );
      expect(state.settings.selectedBackdropId, isNull);
    });

    test('内置壁纸选择在缓存行缺失时仍然有效', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      addTearDown(database.close);

      await repository.saveSettings(
        const AppBackdropSettings(
          enabled: true,
          selectedBackdropId: bundledDefaultWallpaperId,
        ),
      );
      final state = await repository.loadState();

      expect(state.selectedBackdrop, isNull);
      expect(state.settings.selectedBackdropId, bundledDefaultWallpaperId);
    });
  });

  group('背景素材 Web 解码标记', () {
    test('服务端字段缺失时按可播处理', () {
      final asset = BackdropServerAsset.fromJson(const {
        'id': 's1',
        'title': 'clip',
        'mediaType': 'video',
        'status': 'READY',
        'fileSize': 4096,
      });

      expect(asset.videoCodec, isNull);
      expect(asset.webPlayable, isTrue);
    });

    test('解析服务端探测出的编码与可播判定', () {
      final asset = BackdropServerAsset.fromJson(const {
        'id': 's1',
        'title': 'clip',
        'mediaType': 'video',
        'status': 'READY',
        'fileSize': 4096,
        'videoCodec': 'hevc',
        'webPlayable': false,
      });

      expect(asset.videoCodec, 'hevc');
      expect(asset.webPlayable, isFalse);
    });

    test('不可播判定只作用于视频素材', () {
      AppBackdropAsset withFlags(AppBackdropMediaType type, bool webPlayable) =>
          _backdrop(
            'codec-case',
          ).copyWith(mediaType: type, webPlayable: webPlayable);

      expect(
        withFlags(AppBackdropMediaType.video, false).isWebPlaybackUnsupported,
        isTrue,
      );
      expect(
        withFlags(AppBackdropMediaType.video, true).isWebPlaybackUnsupported,
        isFalse,
      );
      expect(
        withFlags(AppBackdropMediaType.image, false).isWebPlaybackUnsupported,
        isFalse,
      );
    });

    test('编码与可播标记随仓储往返保留', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      addTearDown(database.close);
      final original = _backdrop('codec-row').copyWith(
        mediaType: AppBackdropMediaType.video,
        videoCodec: 'hevc',
        webPlayable: false,
      );

      await repository.upsertBackdrops([original]);
      final loaded = await repository.loadState();
      final restored = loaded.backdrops.singleWhere(
        (backdrop) => backdrop.id == 'codec-row',
      );

      expect(restored.videoCodec, 'hevc');
      expect(restored.webPlayable, isFalse);
      expect(restored.isWebPlaybackUnsupported, isTrue);
    });
  });
}

AppBackdropAsset _backdrop(String id) {
  return AppBackdropAsset(
    id: id,
    path: '',
    title: id,
    mediaType: AppBackdropMediaType.image,
    sourceType: AppBackdropSourceType.server,
    fileSize: 1024,
    modifiedAt: DateTime(2026),
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}
