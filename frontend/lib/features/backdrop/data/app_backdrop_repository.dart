import 'package:drift/drift.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_api.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';

/// 应用本机背景库本地存储。
class AppBackdropRepository {
  const AppBackdropRepository(this._db);

  static const settingsId = 'application';
  static const _legacyDefaultDimAmount = 0.34;

  final LocalDatabase _db;

  /// 监听本机背景库状态。
  Stream<AppBackdropState> watchState() {
    final backdropsStream = (_db.select(_db.appBackdropAssets)..orderBy([
      (table) => OrderingTerm.desc(table.updatedAt),
    ])).watch().map((rows) => rows.map(_mapBackdrop).toList(growable: false));
    final settingsStream = (_db.select(_db.appBackdropSettingsTable)..where(
      (table) => table.id.equals(settingsId),
    )).watchSingleOrNull().map(_mapSettings);
    return backdropsStream.asyncMap((backdrops) async {
      final settings = await settingsStream.first;
      return AppBackdropState(
        backdrops: backdrops,
        settings: _normalizeSelection(settings, backdrops),
      );
    });
  }

  /// 读取本机背景库状态。
  Future<AppBackdropState> loadState() async {
    final rows =
        await (_db.select(_db.appBackdropAssets)
          ..orderBy([(table) => OrderingTerm.desc(table.updatedAt)])).get();
    final settingsRow =
        await (_db.select(_db.appBackdropSettingsTable)
          ..where((table) => table.id.equals(settingsId))).getSingleOrNull();
    final backdrops = rows.map(_mapBackdrop).toList(growable: false);
    final settings = _normalizeSelection(_mapSettings(settingsRow), backdrops);
    return AppBackdropState(backdrops: backdrops, settings: settings);
  }

  /// 读取当前背景设置。
  Future<AppBackdropSettings> loadSettings() async {
    final row =
        await (_db.select(_db.appBackdropSettingsTable)
          ..where((table) => table.id.equals(settingsId))).getSingleOrNull();
    return _mapSettings(row);
  }

  /// 保存本机背景素材。
  Future<void> upsertBackdrops(List<AppBackdropAsset> backdrops) async {
    if (backdrops.isEmpty) {
      return;
    }
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(
        _db.appBackdropAssets,
        backdrops.map(_toBackdropCompanion).toList(growable: false),
      );
    });
  }

  /// 注册安装包内置背景;首次使用时建立默认设置,已有设置但无可用选中时回落内置壁纸。
  Future<void> ensureBundledBackdrop(AppBackdropAsset backdrop) async {
    await _db.transaction(() async {
      // 清理旧版本内置壁纸行(如 v1→v2 升级残留),保持"内置素材唯一"
      // 不变式;否则按 sourceType 的唯一性查询会命中多行。
      await (_db.delete(_db.appBackdropAssets)..where(
        (table) =>
            table.sourceType.equals(AppBackdropSourceType.bundled.value) &
            table.id.isNotValue(backdrop.id),
      )).go();
      await _db
          .into(_db.appBackdropAssets)
          .insertOnConflictUpdate(_toBackdropCompanion(backdrop));
      final settingsRow =
          await (_db.select(_db.appBackdropSettingsTable)
            ..where((table) => table.id.equals(settingsId))).getSingleOrNull();
      if (settingsRow == null) {
        await saveSettings(
          AppBackdropSettings(
            enabled: true,
            selectedBackdropId: backdrop.id,
            desktopBackdropId: backdrop.id,
            mobileBackdropId: backdrop.id,
          ),
        );
        return;
      }
      final settings = _mapSettings(settingsRow);
      final hasSelection =
          settings.selectedBackdropId != null ||
          settings.desktopBackdropId != null ||
          settings.mobileBackdropId != null;
      if (!hasSelection) {
        await saveSettings(
          settings.copyWith(
            selectedBackdropId: backdrop.id,
            desktopBackdropId: backdrop.id,
            mobileBackdropId: backdrop.id,
            enabled: true,
          ),
        );
      }
    });
  }

  /// 将服务端素材写入本地缓存;非 READY 状态映射为 missing,不参与选择。
  /// path 缓存签名内容 URL、thumbnailPath 缓存缩略图 URL(过期由下次列表刷新),
  /// 渲染层据此取图,图片缓存键仍基于素材 ID。
  /// contentUrl/thumbUrl 为空时保留原缓存,避免签名生成失败把可用路径清空。
  Future<void> upsertServerAssets(List<BackdropServerAsset> assets) async {
    if (assets.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final existingById = <String, AppBackdropAsset>{};
    final rows = await (_db.select(_db.appBackdropAssets)).get();
    for (final row in rows) {
      existingById[row.id] = _mapBackdrop(row);
    }
    final mapped = assets
        .map((asset) {
          final updatedAt = asset.updatedAt ?? now;
          final status = AppBackdropAssetStatus.fromValue(asset.status);
          final existing = existingById[asset.id];
          final contentUrl = asset.contentUrl;
          final thumbUrl = asset.thumbUrl;
          return AppBackdropAsset(
            id: asset.id,
            path:
                (contentUrl != null && contentUrl.isNotEmpty)
                    ? contentUrl
                    : existing?.path ?? '',
            title: asset.title,
            mediaType: AppBackdropMediaType.fromValue(asset.mediaType),
            sourceType: AppBackdropSourceType.server,
            fileSize: asset.fileSize,
            modifiedAt: updatedAt,
            width: asset.width ?? existing?.width,
            height: asset.height ?? existing?.height,
            durationMs: asset.durationMs ?? existing?.durationMs,
            thumbnailPath:
                (thumbUrl != null && thumbUrl.isNotEmpty)
                    ? thumbUrl
                    : existing?.thumbnailPath,
            missing: status != AppBackdropAssetStatus.ready,
            status: status,
            createdAt: updatedAt,
            updatedAt: updatedAt,
          );
        })
        .toList(growable: false);
    await upsertBackdrops(mapped);
  }

  /// 删除本机背景素材。
  Future<void> removeBackdrop(String id) async {
    await _db.transaction(() async {
      final target =
          await (_db.select(_db.appBackdropAssets)
            ..where((table) => table.id.equals(id))).getSingleOrNull();
      if (target?.sourceType == AppBackdropSourceType.bundled.value) {
        return;
      }
      final currentSettings =
          await (_db.select(_db.appBackdropSettingsTable)
            ..where((table) => table.id.equals(settingsId))).getSingleOrNull();
      await (_db.delete(_db.appBackdropAssets)
        ..where((table) => table.id.equals(id))).go();
      final mappedSettings = _mapSettings(currentSettings);
      final referencesBackdrop =
          mappedSettings.selectedBackdropId == id ||
          mappedSettings.desktopBackdropId == id ||
          mappedSettings.mobileBackdropId == id;
      if (referencesBackdrop) {
        await saveSettings(mappedSettings.removeBackdropSelection(id));
      }
    });
  }

  /// 清空本机背景库索引和设置。
  Future<void> clearBackdrops() async {
    await _db.transaction(() async {
      await (_db.delete(_db.appBackdropAssets)..where(
        (table) =>
            table.sourceType.isNotValue(AppBackdropSourceType.bundled.value),
      )).go();
      // 防御式读取:历史升级库中可能短暂存在多行内置素材(注册器会清理),
      // 不得因多行抛 StateError 阻断清空。
      final bundledRows =
          await (_db.select(_db.appBackdropAssets)..where(
            (table) =>
                table.sourceType.equals(AppBackdropSourceType.bundled.value),
          )).get();
      final bundled = bundledRows.isEmpty ? null : bundledRows.first;
      final settingsRow =
          await (_db.select(_db.appBackdropSettingsTable)
            ..where((table) => table.id.equals(settingsId))).getSingleOrNull();
      if (bundled == null || settingsRow == null) {
        return;
      }
      final settings = _mapSettings(settingsRow);
      await saveSettings(
        settings.copyWith(
          selectedBackdropId: bundled.id,
          desktopBackdropId: bundled.id,
          mobileBackdropId: bundled.id,
        ),
      );
    });
  }

  /// 保存本机背景设置。
  Future<void> saveSettings(AppBackdropSettings settings) async {
    await _db
        .into(_db.appBackdropSettingsTable)
        .insertOnConflictUpdate(
          AppBackdropSettingsTableCompanion.insert(
            id: settingsId,
            enabled: Value(settings.enabled),
            selectedBackdropId: Value(settings.selectedBackdropId),
            separateDeviceBackdrops: Value(settings.separateDeviceBackdrops),
            desktopBackdropId: Value(settings.desktopBackdropId),
            mobileBackdropId: Value(settings.mobileBackdropId),
            fit: Value(settings.fit.value),
            alignment: Value(settings.alignment.value),
            dimAmount: Value(settings.dimAmount),
            blurAmount: Value(settings.blurAmount),
            videoMuted: Value(settings.videoMuted),
            updatedAt: DateTime.now(),
          ),
        );
  }

  /// 更新素材缺失状态。
  Future<void> updateMissing(Map<String, bool> missingById) async {
    if (missingById.isEmpty) {
      return;
    }
    await _db.batch((batch) {
      for (final entry in missingById.entries) {
        batch.update(
          _db.appBackdropAssets,
          AppBackdropAssetsCompanion(
            missing: Value(entry.value),
            updatedAt: Value(DateTime.now()),
          ),
          where: (table) => table.id.equals(entry.key),
        );
      }
    });
  }

  AppBackdropSettings _normalizeSelection(
    AppBackdropSettings settings,
    List<AppBackdropAsset> backdrops,
  ) {
    final availableIds =
        backdrops
            .where((backdrop) => backdrop.isSelectable)
            .map((backdrop) => backdrop.id)
            .toSet();
    final sharedId = _availableSelection(
      settings.selectedBackdropId,
      availableIds,
    );
    final desktopId = _availableSelection(
      settings.desktopBackdropId,
      availableIds,
    );
    final mobileId = _availableSelection(
      settings.mobileBackdropId,
      availableIds,
    );
    final normalized = settings.copyWith(
      selectedBackdropId: sharedId,
      clearSelectedBackdropId: sharedId == null,
      desktopBackdropId: desktopId,
      clearDesktopBackdropId: desktopId == null,
      mobileBackdropId: mobileId,
      clearMobileBackdropId: mobileId == null,
    );
    // 非设备分离时保持三槽位一致,避免 desktop/mobile 残留旧 ID 造成选中抖动。
    final aligned =
        normalized.separateDeviceBackdrops
            ? normalized
            : normalized.copyWith(
              selectedBackdropId: sharedId,
              clearSelectedBackdropId: sharedId == null,
              desktopBackdropId: sharedId,
              clearDesktopBackdropId: sharedId == null,
              mobileBackdropId: sharedId,
              clearMobileBackdropId: sharedId == null,
            );
    final hasUsableSelection =
        aligned.separateDeviceBackdrops
            ? aligned.desktopBackdropId != null ||
                aligned.mobileBackdropId != null
            : aligned.selectedBackdropId != null;
    return aligned.copyWith(enabled: aligned.enabled && hasUsableSelection);
  }

  String? _availableSelection(String? id, Set<String> availableIds) {
    // 内置壁纸三端恒可用,不依赖缓存行是否存在。
    if (id != null && id == bundledDefaultWallpaperId) {
      return id;
    }
    if (id == null || id.isEmpty || !availableIds.contains(id)) {
      return null;
    }
    return id;
  }

  AppBackdropAsset _mapBackdrop(AppBackdropAssetRow row) {
    return AppBackdropAsset(
      id: row.id,
      path: row.path,
      title: row.title,
      mediaType: AppBackdropMediaType.fromValue(row.mediaType),
      sourceType: AppBackdropSourceType.fromValue(row.sourceType),
      sourceDirectory: row.sourceDirectory,
      fileSize: row.fileSize,
      modifiedAt: row.modifiedAt,
      width: row.width,
      height: row.height,
      durationMs: row.durationMs,
      thumbnailPath: row.thumbnailPath,
      missing: row.missing,
      status: AppBackdropAssetStatus.fromValue(row.status),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  AppBackdropSettings _mapSettings(AppBackdropSettingRow? row) {
    if (row == null) {
      return const AppBackdropSettings();
    }
    return AppBackdropSettings(
      enabled: row.enabled,
      selectedBackdropId: row.selectedBackdropId,
      separateDeviceBackdrops: row.separateDeviceBackdrops,
      desktopBackdropId: row.desktopBackdropId,
      mobileBackdropId: row.mobileBackdropId,
      fit: AppBackdropFit.fromValue(row.fit),
      alignment: AppBackdropAlignment.fromValue(row.alignment),
      dimAmount: _normalizeDimAmount(row.dimAmount),
      blurAmount: row.blurAmount,
      videoMuted: row.videoMuted,
    );
  }

  double _normalizeDimAmount(double value) {
    if ((value - _legacyDefaultDimAmount).abs() < 0.0001) {
      return const AppBackdropSettings().dimAmount;
    }
    return value;
  }

  AppBackdropAssetsCompanion _toBackdropCompanion(AppBackdropAsset backdrop) {
    return AppBackdropAssetsCompanion.insert(
      id: backdrop.id,
      path: backdrop.path,
      title: backdrop.title,
      mediaType: backdrop.mediaType.value,
      sourceType: backdrop.sourceType.value,
      sourceDirectory: Value(backdrop.sourceDirectory),
      fileSize: Value(backdrop.fileSize),
      modifiedAt: backdrop.modifiedAt,
      width: Value(backdrop.width),
      height: Value(backdrop.height),
      durationMs: Value(backdrop.durationMs),
      thumbnailPath: Value(backdrop.thumbnailPath),
      missing: Value(backdrop.missing),
      status: Value(backdrop.status.value),
      createdAt: backdrop.createdAt,
      updatedAt: backdrop.updatedAt,
    );
  }
}
