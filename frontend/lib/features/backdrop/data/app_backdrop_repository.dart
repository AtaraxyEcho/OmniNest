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

  /// 注册安装包内置背景，并仅为首次使用背景库的用户建立默认设置。
  Future<void> ensureBundledBackdrop(AppBackdropAsset backdrop) async {
    await _db.transaction(() async {
      await _db
          .into(_db.appBackdropAssets)
          .insertOnConflictUpdate(_toBackdropCompanion(backdrop));
      final settingsRow =
          await (_db.select(_db.appBackdropSettingsTable)
            ..where((table) => table.id.equals(settingsId))).getSingleOrNull();
      if (settingsRow != null) {
        return;
      }
      await saveSettings(
        AppBackdropSettings(
          enabled: true,
          selectedBackdropId: backdrop.id,
          desktopBackdropId: backdrop.id,
          mobileBackdropId: backdrop.id,
        ),
      );
    });
  }

  /// 将服务端素材写入本地缓存;非 READY 状态映射为 missing,不参与选择。
  /// path 缓存签名内容 URL、thumbnailPath 缓存缩略图 URL(过期由下次列表刷新),
  /// 渲染层据此取图,图片缓存键仍基于素材 ID。
  Future<void> upsertServerAssets(List<BackdropServerAsset> assets) async {
    if (assets.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final mapped = assets
        .map((asset) {
          final updatedAt = asset.updatedAt ?? now;
          return AppBackdropAsset(
            id: asset.id,
            path: asset.contentUrl ?? '',
            title: asset.title,
            mediaType: AppBackdropMediaType.fromValue(asset.mediaType),
            sourceType: AppBackdropSourceType.server,
            fileSize: asset.fileSize,
            modifiedAt: updatedAt,
            width: asset.width,
            height: asset.height,
            durationMs: asset.durationMs,
            thumbnailPath: asset.thumbUrl,
            missing: !asset.isSelectable,
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
      final bundled =
          await (_db.select(_db.appBackdropAssets)..where(
            (table) =>
                table.sourceType.equals(AppBackdropSourceType.bundled.value),
          )).getSingleOrNull();
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
            .where((backdrop) => !backdrop.missing)
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
    final hasUsableSelection =
        normalized.separateDeviceBackdrops
            ? desktopId != null || mobileId != null
            : sharedId != null;
    return normalized.copyWith(
      enabled: normalized.enabled && hasUsableSelection,
    );
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
      createdAt: backdrop.createdAt,
      updatedAt: backdrop.updatedAt,
    );
  }
}
