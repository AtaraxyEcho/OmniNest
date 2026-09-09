/// 应用本机背景媒体类型。
enum AppBackdropMediaType {
  image('image'),
  gif('gif'),
  video('video');

  const AppBackdropMediaType(this.value);

  final String value;

  static AppBackdropMediaType fromValue(Object? value) {
    final text = value?.toString();
    return AppBackdropMediaType.values.firstWhere(
      (type) => type.value == text,
      orElse: () => AppBackdropMediaType.image,
    );
  }
}

/// 内置动态壁纸的稳定素材 ID,三端一致且不受服务端素材库影响。
const String bundledDefaultWallpaperId = 'bundled-default-wallpaper-v1';

/// 内置动态壁纸在 Web 端的打包资产地址(HTML video 直接加载)。
const String bundledDefaultWallpaperWebAsset =
    'assets/backdrops/default_wallpaper.mp4';

/// 应用背景来源类型。
enum AppBackdropSourceType {
  bundled('bundled'),
  server('server');

  const AppBackdropSourceType(this.value);

  final String value;

  static AppBackdropSourceType fromValue(Object? value) {
    final text = value?.toString();
    return AppBackdropSourceType.values.firstWhere(
      (type) => type.value == text,
      orElse: () => AppBackdropSourceType.bundled,
    );
  }
}

/// 应用本机背景适配方式。
enum AppBackdropFit {
  cover('cover'),
  contain('contain');

  const AppBackdropFit(this.value);

  final String value;

  static AppBackdropFit fromValue(Object? value) {
    final text = value?.toString();
    return AppBackdropFit.values.firstWhere(
      (fit) => fit.value == text,
      orElse: () => AppBackdropFit.cover,
    );
  }
}

/// 应用背景选择对应的设备类别。
enum AppBackdropSelectionTarget { desktop, mobile }

/// 应用本机背景操作消息。
enum AppBackdropMessage { emptyScan, scanFailed }

/// 应用本机背景素材。
class AppBackdropAsset {
  const AppBackdropAsset({
    required this.id,
    required this.path,
    required this.title,
    required this.mediaType,
    required this.sourceType,
    required this.fileSize,
    required this.modifiedAt,
    required this.createdAt,
    required this.updatedAt,
    this.sourceDirectory,
    this.width,
    this.height,
    this.durationMs,
    this.thumbnailPath,
    this.missing = false,
  });

  final String id;

  /// 素材引用:bundled 为本机路径或 Web 打包资产地址,server 素材为空串。
  final String path;
  final String title;
  final AppBackdropMediaType mediaType;
  final AppBackdropSourceType sourceType;
  final String? sourceDirectory;
  final int fileSize;
  final DateTime modifiedAt;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? thumbnailPath;
  final bool missing;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isVideo => mediaType == AppBackdropMediaType.video;

  /// 当前素材是否随应用安装包提供。
  bool get isBundled => sourceType == AppBackdropSourceType.bundled;

  AppBackdropAsset copyWith({
    String? id,
    String? path,
    String? title,
    AppBackdropMediaType? mediaType,
    AppBackdropSourceType? sourceType,
    String? sourceDirectory,
    int? fileSize,
    DateTime? modifiedAt,
    int? width,
    int? height,
    int? durationMs,
    String? thumbnailPath,
    bool? missing,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppBackdropAsset(
      id: id ?? this.id,
      path: path ?? this.path,
      title: title ?? this.title,
      mediaType: mediaType ?? this.mediaType,
      sourceType: sourceType ?? this.sourceType,
      sourceDirectory: sourceDirectory ?? this.sourceDirectory,
      fileSize: fileSize ?? this.fileSize,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      missing: missing ?? this.missing,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 应用本机背景设置。
class AppBackdropSettings {
  const AppBackdropSettings({
    this.enabled = false,
    this.selectedBackdropId,
    this.separateDeviceBackdrops = false,
    this.desktopBackdropId,
    this.mobileBackdropId,
    this.fit = AppBackdropFit.cover,
    this.dimAmount = 0.08,
    this.blurAmount = 0.0,
    this.videoMuted = true,
  });

  final bool enabled;
  final String? selectedBackdropId;
  final bool separateDeviceBackdrops;
  final String? desktopBackdropId;
  final String? mobileBackdropId;
  final AppBackdropFit fit;
  final double dimAmount;
  final double blurAmount;
  final bool videoMuted;

  /// 返回指定设备类别当前使用的背景素材 ID。
  String? selectedBackdropIdFor(AppBackdropSelectionTarget target) {
    if (!separateDeviceBackdrops) {
      return selectedBackdropId;
    }
    return switch (target) {
      AppBackdropSelectionTarget.desktop => desktopBackdropId,
      AppBackdropSelectionTarget.mobile => mobileBackdropId,
    };
  }

  /// 更新指定设备类别的背景选择。
  AppBackdropSettings selectBackdropFor(
    AppBackdropSelectionTarget target,
    String id,
  ) {
    if (!separateDeviceBackdrops) {
      return copyWith(selectedBackdropId: id);
    }
    return switch (target) {
      AppBackdropSelectionTarget.desktop => copyWith(desktopBackdropId: id),
      AppBackdropSelectionTarget.mobile => copyWith(mobileBackdropId: id),
    };
  }

  /// 切换桌面端和移动端背景选择是否隔离。
  AppBackdropSettings withDeviceSeparation(
    bool separate,
    AppBackdropSelectionTarget currentTarget,
  ) {
    if (separate == separateDeviceBackdrops) {
      return this;
    }
    if (separate) {
      return copyWith(
        separateDeviceBackdrops: true,
        desktopBackdropId: desktopBackdropId ?? selectedBackdropId,
        mobileBackdropId: mobileBackdropId ?? selectedBackdropId,
      );
    }
    final currentSelection = selectedBackdropIdFor(currentTarget);
    return copyWith(
      separateDeviceBackdrops: false,
      selectedBackdropId: currentSelection ?? selectedBackdropId,
    );
  }

  /// 清除所有引用指定素材的背景选择。
  AppBackdropSettings removeBackdropSelection(String id) {
    return copyWith(
      clearSelectedBackdropId: selectedBackdropId == id,
      clearDesktopBackdropId: desktopBackdropId == id,
      clearMobileBackdropId: mobileBackdropId == id,
    );
  }

  AppBackdropSettings copyWith({
    bool? enabled,
    String? selectedBackdropId,
    bool clearSelectedBackdropId = false,
    bool? separateDeviceBackdrops,
    String? desktopBackdropId,
    bool clearDesktopBackdropId = false,
    String? mobileBackdropId,
    bool clearMobileBackdropId = false,
    AppBackdropFit? fit,
    double? dimAmount,
    double? blurAmount,
    bool? videoMuted,
  }) {
    return AppBackdropSettings(
      enabled: enabled ?? this.enabled,
      selectedBackdropId:
          clearSelectedBackdropId
              ? null
              : selectedBackdropId ?? this.selectedBackdropId,
      separateDeviceBackdrops:
          separateDeviceBackdrops ?? this.separateDeviceBackdrops,
      desktopBackdropId:
          clearDesktopBackdropId
              ? null
              : desktopBackdropId ?? this.desktopBackdropId,
      mobileBackdropId:
          clearMobileBackdropId
              ? null
              : mobileBackdropId ?? this.mobileBackdropId,
      fit: fit ?? this.fit,
      dimAmount: (dimAmount ?? this.dimAmount).clamp(0.0, 0.86),
      blurAmount: (blurAmount ?? this.blurAmount).clamp(0.0, 18.0),
      videoMuted: videoMuted ?? this.videoMuted,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppBackdropSettings &&
        other.enabled == enabled &&
        other.selectedBackdropId == selectedBackdropId &&
        other.separateDeviceBackdrops == separateDeviceBackdrops &&
        other.desktopBackdropId == desktopBackdropId &&
        other.mobileBackdropId == mobileBackdropId &&
        other.fit == fit &&
        other.dimAmount == dimAmount &&
        other.blurAmount == blurAmount &&
        other.videoMuted == videoMuted;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    selectedBackdropId,
    separateDeviceBackdrops,
    desktopBackdropId,
    mobileBackdropId,
    fit,
    dimAmount,
    blurAmount,
    videoMuted,
  );
}

/// 单个上传失败条目;code 为后端稳定错误码(字符串数字)供界面映射文案。
class BackdropUploadFailure {
  const BackdropUploadFailure({required this.title, required this.code});

  final String title;
  final String code;
}

/// 应用背景库状态。
class AppBackdropState {
  const AppBackdropState({
    this.backdrops = const <AppBackdropAsset>[],
    this.settings = const AppBackdropSettings(),
    this.selectionTarget = AppBackdropSelectionTarget.desktop,
    this.isScanning = false,
    this.uploading = false,
    this.failedUploads = const <BackdropUploadFailure>[],
    this.message,
  });

  final List<AppBackdropAsset> backdrops;
  final AppBackdropSettings settings;
  final AppBackdropSelectionTarget selectionTarget;
  final bool isScanning;

  /// 是否有上传批次进行中。
  final bool uploading;

  /// 最近一批上传失败的条目(标题+错误码),由界面映射文案。
  final List<BackdropUploadFailure> failedUploads;

  final AppBackdropMessage? message;

  /// 当前设备类别使用的背景素材 ID。
  String? get selectedBackdropId {
    return settings.selectedBackdropIdFor(selectionTarget);
  }

  AppBackdropAsset? get selectedBackdrop {
    final selectedId = selectedBackdropId;
    if (selectedId == null || selectedId.isEmpty) {
      return null;
    }
    for (final backdrop in backdrops) {
      if (backdrop.id == selectedId) {
        return backdrop;
      }
    }
    return null;
  }

  /// 当前是否存在已启用且可访问的背景素材。
  bool get hasActiveBackdrop {
    final selected = selectedBackdrop;
    return settings.enabled && selected != null && !selected.missing;
  }

  AppBackdropState copyWith({
    List<AppBackdropAsset>? backdrops,
    AppBackdropSettings? settings,
    AppBackdropSelectionTarget? selectionTarget,
    bool? isScanning,
    bool? uploading,
    List<BackdropUploadFailure>? failedUploads,
    bool clearUploadFailures = false,
    AppBackdropMessage? message,
    bool clearMessage = false,
  }) {
    return AppBackdropState(
      backdrops: backdrops ?? this.backdrops,
      settings: settings ?? this.settings,
      selectionTarget: selectionTarget ?? this.selectionTarget,
      isScanning: isScanning ?? this.isScanning,
      uploading: uploading ?? this.uploading,
      failedUploads:
          clearUploadFailures
              ? const <BackdropUploadFailure>[]
              : failedUploads ?? this.failedUploads,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}
