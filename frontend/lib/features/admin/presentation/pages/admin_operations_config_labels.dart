/// 配置中心文案映射与判定：分组归类、标题、描述、当前值摘要与敏感判定。
part of 'admin_operations_pages.dart';

bool _isRemovedConfigKey(String key) {
  return const {
    'media.metadata-providers.enabled',
    'reader.metadata-providers.enabled',
    'reader.metadata-provider.open-library.timeout-seconds',
    'reader.metadata-provider.open-library.max-results',
    'music.metadata-providers.enabled',
    'music.metadata-provider.musicbrainz.request-delay-ms',
    'music.platform.netease.request-delay-ms',
    'music.qq.enabled',
    'music.qq.u-url',
    'music.qq.c-url',
    'music.qq.hosts',
    'media.subtitle.key',
    'media.subtitle.opensubtitles-api-key',
    'photo.geo.cache-enabled',
    'upload.bandwidth.max-parts-per-second',
    'upload.bandwidth.burst-capacity',
    'security.clamav.timeout-millis',
    'file.local-media.enabled',
    'file.local-media.max-files-per-scan',
    'file.local-media.max-scan-depth',
  }.contains(key);
}

/// 分组排列序号：provider 前缀分组在前，其余按模块类别顺序，
/// 保证统一表格内同组相邻、组间按稳定顺序排列。
int _configGroupOrder(AdminConfigEntry entry) {
  final key = entry.key;
  if (_startsWithAny(key, const [
    'music.musicbrainz',
    'music.metadata-provider.musicbrainz',
  ])) {
    return 0;
  }
  if (_startsWithAny(key, const [
    'media.tmdb',
    'media.metadata-provider.tmdb',
  ])) {
    return 1;
  }
  if (_startsWithAny(key, const [
    'reader.gbooks',
    'reader.metadata-provider.google-books',
  ])) {
    return 2;
  }
  if (_startsWithAny(key, const [
    'reader.openlib',
    'reader.metadata-provider.open-library',
  ])) {
    return 3;
  }
  if (key.startsWith('photo.ai')) {
    return 4;
  }
  if (_startsWithAny(key, const ['music.netease', 'music.platform.netease'])) {
    return 5;
  }
  if (key.startsWith('weather.qweather')) {
    return 7;
  }
  return 9 + _configCategoryOrder(entry.category);
}

int _configCategoryOrder(String category) {
  return switch (category) {
    'media' => 0,
    'reader' => 1,
    'music' => 2,
    'photo' => 3,
    'storage' => 4,
    'upload' => 5,
    'security' => 6,
    'auth' => 7,
    'weather' => 8,
    'backdrop' => 9,
    'general' => 10,
    _ => 11,
  };
}

String _configGroup(AppLocalizations l10n, AdminConfigEntry entry) {
  if (_startsWithAny(entry.key, const [
    'music.musicbrainz',
    'music.metadata-provider.musicbrainz',
  ])) {
    return l10n.adminConfigProviderMusicBrainz;
  }
  if (_startsWithAny(entry.key, const [
    'media.tmdb',
    'media.metadata-provider.tmdb',
  ])) {
    return l10n.adminConfigProviderTmdb;
  }
  if (_startsWithAny(entry.key, const [
    'reader.gbooks',
    'reader.metadata-provider.google-books',
  ])) {
    return l10n.adminConfigProviderGoogleBooks;
  }
  if (_startsWithAny(entry.key, const [
    'reader.openlib',
    'reader.metadata-provider.open-library',
  ])) {
    return l10n.adminConfigProviderOpenLibrary;
  }
  if (entry.key.startsWith('photo.ai')) {
    return l10n.adminConfigProviderPhotoAi;
  }
  if (_startsWithAny(entry.key, const [
    'music.netease',
    'music.platform.netease',
  ])) {
    return l10n.adminConfigProviderNetease;
  }
  if (entry.key.startsWith('weather.qweather')) {
    return l10n.adminConfigProviderQWeather;
  }
  return switch (entry.category) {
    'media' => l10n.adminConfigGroupMedia,
    'reader' => l10n.adminConfigGroupReader,
    'music' => l10n.adminConfigGroupMusic,
    'photo' => l10n.adminConfigGroupPhotos,
    'storage' => l10n.adminConfigGroupStorage,
    'upload' => l10n.adminConfigGroupUpload,
    'security' => l10n.adminConfigGroupSecurity,
    'auth' => l10n.adminConfigGroupAuth,
    'weather' => l10n.adminConfigGroupWeather,
    'backdrop' => l10n.adminConfigGroupBackdrop,
    'general' => l10n.adminConfigGroupSystem,
    _ => l10n.adminConfigGroupOther,
  };
}

bool _startsWithAny(String value, List<String> prefixes) {
  return prefixes.any(value.startsWith);
}

String _configTitle(AppLocalizations l10n, AdminConfigEntry entry) {
  final keyTitle =
      <String, String>{
        'media.tmdb.enabled': l10n.adminConfigTmdbEnabled,
        'media.metadata-provider.tmdb.enabled': l10n.adminConfigTmdbEnabled,
        'media.tmdb.token': l10n.adminConfigTmdbAccessToken,
        'media.metadata-provider.tmdb.access-token':
            l10n.adminConfigTmdbAccessToken,
        'media.tmdb.key': l10n.adminConfigTmdbApiKey,
        'media.metadata-provider.tmdb.api-key': l10n.adminConfigTmdbApiKey,
        'media.tmdb.url': l10n.adminConfigTmdbBaseUrl,
        'media.metadata-provider.tmdb.base-url': l10n.adminConfigTmdbBaseUrl,
        'media.tmdb.lang': l10n.adminConfigTmdbLanguage,
        'media.metadata-provider.tmdb.language': l10n.adminConfigTmdbLanguage,
        'media.tmdb.timeout': l10n.adminConfigTmdbTimeout,
        'media.metadata-provider.tmdb.timeout-seconds':
            l10n.adminConfigTmdbTimeout,
        'media.tmdb.strategy': l10n.adminConfigTmdbStrategy,
        'media.metadata-provider.tmdb.search-queries-strategy':
            l10n.adminConfigTmdbStrategy,
        'media.tmdb.limit': l10n.adminConfigTmdbLimit,
        'media.metadata-provider.tmdb.max-results': l10n.adminConfigTmdbLimit,
        'media.tmdb.adult': l10n.adminConfigTmdbAdult,
        'media.metadata-provider.tmdb.include-adult': l10n.adminConfigTmdbAdult,
        'media.transcode.enabled': l10n.adminConfigMediaTranscode,
        'transcode.enabled': l10n.adminConfigMediaTranscode,
        'media.import.enabled': l10n.adminConfigMediaAutoImport,
        'media.auto-import.enabled': l10n.adminConfigMediaAutoImport,
        'reader.gbooks.enabled': l10n.adminConfigReaderGoogleBooksEnabled,
        'reader.metadata-provider.google-books.enabled':
            l10n.adminConfigReaderGoogleBooksEnabled,
        'reader.gbooks.url': l10n.adminConfigReaderGoogleBooksUrl,
        'reader.metadata-provider.google-books.base-url':
            l10n.adminConfigReaderGoogleBooksUrl,
        'reader.gbooks.lang': l10n.adminConfigReaderGoogleBooksLanguage,
        'reader.metadata-provider.google-books.language':
            l10n.adminConfigReaderGoogleBooksLanguage,
        'reader.gbooks.limit': l10n.adminConfigReaderGoogleBooksLimit,
        'reader.metadata-provider.google-books.max-results':
            l10n.adminConfigReaderGoogleBooksLimit,
        'reader.gbooks.timeout': l10n.adminConfigReaderGoogleBooksTimeout,
        'reader.metadata-provider.google-books.timeout-seconds':
            l10n.adminConfigReaderGoogleBooksTimeout,
        'reader.gbooks.key': l10n.adminConfigReaderGoogleBooksApiKey,
        'reader.metadata-provider.google-books.api-key':
            l10n.adminConfigReaderGoogleBooksApiKey,
        'reader.openlib.enabled': l10n.adminConfigReaderOpenLibraryEnabled,
        'reader.metadata-provider.open-library.enabled':
            l10n.adminConfigReaderOpenLibraryEnabled,
        'reader.openlib.url': l10n.adminConfigReaderOpenLibraryUrl,
        'reader.metadata-provider.open-library.base-url':
            l10n.adminConfigReaderOpenLibraryUrl,
        'reader.openlib.lang': l10n.adminConfigReaderOpenLibraryLanguage,
        'reader.metadata-provider.open-library.language':
            l10n.adminConfigReaderOpenLibraryLanguage,
        'reader.import.enabled': l10n.adminConfigReaderAutoImport,
        'reader.auto-import.enabled': l10n.adminConfigReaderAutoImport,
        'music.musicbrainz.enabled': l10n.adminConfigMusicBrainzEnabled,
        'music.metadata-provider.musicbrainz.enabled':
            l10n.adminConfigMusicBrainzEnabled,
        'music.import.enabled': l10n.adminConfigMusicAutoImport,
        'music.auto-import.enabled': l10n.adminConfigMusicAutoImport,
        'music.musicbrainz.url': l10n.adminConfigMusicBrainzBaseUrl,
        'music.metadata-provider.musicbrainz.base-url':
            l10n.adminConfigMusicBrainzBaseUrl,
        'music.musicbrainz.ua': l10n.adminConfigMusicBrainzUserAgent,
        'music.metadata-provider.musicbrainz.user-agent':
            l10n.adminConfigMusicBrainzUserAgent,
        'music.musicbrainz.cover-url': l10n.adminConfigMusicBrainzCoverUrl,
        'music.metadata-provider.musicbrainz.cover-base-url':
            l10n.adminConfigMusicBrainzCoverUrl,
        'music.online.enabled': l10n.adminConfigMusicOnlineEnabled,
        'music.platform.online.enabled': l10n.adminConfigMusicOnlineEnabled,
        'music.netease.enabled': l10n.adminConfigNeteaseEnabled,
        'music.platform.netease.enabled': l10n.adminConfigNeteaseEnabled,
        'music.netease.url': l10n.adminConfigNeteaseBaseUrl,
        'music.platform.netease.base-url': l10n.adminConfigNeteaseBaseUrl,
        'music.netease.hosts': l10n.adminConfigNeteaseHosts,
        'music.platform.netease.playback-host-suffixes':
            l10n.adminConfigNeteaseHosts,
        'photo.ai.enabled': l10n.adminConfigPhotoAiEnabled,
        'photo.ai.url': l10n.adminConfigPhotoAiEndpoint,
        'photo.ai.endpoint': l10n.adminConfigPhotoAiEndpoint,
        'photo.ai.timeout': l10n.adminConfigPhotoAiTimeout,
        'photo.ai.timeout-seconds': l10n.adminConfigPhotoAiTimeout,
        'photo.backup': l10n.adminConfigPhotoBackup,
        'photo.backup.enabled': l10n.adminConfigPhotoBackup,
        'photo.geo.rate': l10n.adminConfigPhotoGeoRate,
        'photo.geo.rate-limit-per-second': l10n.adminConfigPhotoGeoRate,
        'storage.quota.default': l10n.adminConfigDefaultQuota,
        'storage.quota.default.gb': l10n.adminConfigDefaultQuota,
        'storage.quota.warning': l10n.adminConfigQuotaWarning,
        'storage.quota.warning.percent': l10n.adminConfigQuotaWarning,
        'share.enabled': l10n.adminConfigSharedSpace,
        'shared_space.enabled': l10n.adminConfigSharedSpace,
        'share.max-bytes': l10n.adminConfigSharedSpaceLimit,
        'shared_space.max_bytes': l10n.adminConfigSharedSpaceLimit,
        'upload.rate.enabled': l10n.adminConfigUploadRateEnabled,
        'upload.bandwidth.enabled': l10n.adminConfigUploadRateEnabled,
        'security.rate-limit': l10n.adminConfigSecurityRateLimit,
        'rate-limit.default-limit': l10n.adminConfigSecurityRateLimit,
        'clamav.enabled': l10n.adminConfigClamavEnabled,
        'security.clamav.enabled': l10n.adminConfigClamavEnabled,
        'clamav.host': l10n.adminConfigClamavHost,
        'security.clamav.host': l10n.adminConfigClamavHost,
        'clamav.port': l10n.adminConfigClamavPort,
        'security.clamav.port': l10n.adminConfigClamavPort,
        'weather.enabled': l10n.adminConfigWeather,
        'weather.qweather.project': l10n.adminConfigQWeatherProjectId,
        'weather.qweather.project-id': l10n.adminConfigQWeatherProjectId,
        'weather.qweather.credential': l10n.adminConfigQWeatherCredentialId,
        'weather.qweather.credential-id': l10n.adminConfigQWeatherCredentialId,
        'weather.qweather.url': l10n.adminConfigQWeatherBaseUrl,
        'weather.qweather.base-url': l10n.adminConfigQWeatherBaseUrl,
        'weather.qweather.key': l10n.adminConfigQWeatherPrivateKey,
        'weather.qweather.private-key': l10n.adminConfigQWeatherPrivateKey,
        'weather.location': l10n.adminConfigWeatherLocation,
        'log-retention.enabled': l10n.adminConfigLogRetentionEnabled,
        'log-retention.retention-days': l10n.adminConfigLogRetentionDays,
        'log-retention.scan-paths': l10n.adminConfigLogRetentionPaths,
        'photo.geo.offline': l10n.adminConfigPhotoGeoOffline,
        'photo.geo.nominatim': l10n.adminConfigPhotoGeoNominatim,
        'photo.geo.max-distance-km': l10n.adminConfigPhotoGeoMaxDistance,
        'photo.geo.import.batch-size': l10n.adminConfigPhotoGeoImportBatchSize,
        'photo.geo.import.auto': l10n.adminConfigPhotoGeoImportAuto,
        'security.quarantine.retention-days':
            l10n.adminConfigQuarantineRetentionDays,
        'clamav.timeout-millis': l10n.adminConfigClamavTimeout,
        'auth.two-factor.required-roles':
            l10n.adminConfigTwoFactorRequiredRoles,
        'backdrop.max-image-bytes': l10n.adminConfigBackdropMaxImageBytes,
        'backdrop.max-video-bytes': l10n.adminConfigBackdropMaxVideoBytes,
        'backdrop.max-assets-per-user': l10n.adminConfigBackdropMaxAssets,
        'backdrop.upload.rate-per-hour': l10n.adminConfigBackdropUploadRate,
        'app.version.latest': l10n.adminConfigAppVersionLatest,
        'app.version.release-notes-url': l10n.adminConfigAppVersionReleaseNotes,
        'app.version.download-url': l10n.adminConfigAppVersionDownloadUrl,
      }[entry.key];
  if (keyTitle != null) {
    return keyTitle;
  }
  return switch (entry.displayCode) {
    'config.media.autoImport' => l10n.adminConfigMediaAutoImport,
    'config.photo.backup' => l10n.adminConfigPhotoBackup,
    'config.logRetention.enabled' => l10n.adminConfigLogRetentionEnabled,
    'config.logRetention.retentionDays' => l10n.adminConfigLogRetentionDays,
    'config.logRetention.scanPaths' => l10n.adminConfigLogRetentionPaths,
    'config.storage.defaultQuota' => l10n.adminConfigDefaultQuota,
    'config.storage.warningPercent' => l10n.adminConfigQuotaWarning,
    'config.storage.sharedSpace' => l10n.adminConfigSharedSpace,
    'config.storage.sharedSpaceLimit' => l10n.adminConfigSharedSpaceLimit,
    'config.storage.localMedia' => l10n.adminConfigLocalMedia,
    'config.weather.enabled' => l10n.adminConfigWeather,
    'config.integration.musicbrainz.enabled' =>
      l10n.adminConfigMusicBrainzEnabled,
    'config.integration.tmdb.enabled' => l10n.adminConfigTmdbEnabled,
    'config.integration.tmdb.apiKey' => l10n.adminConfigTmdbApiKey,
    'config.integration.tmdb.accessToken' => l10n.adminConfigTmdbAccessToken,
    'config.integration.tmdb.language' => l10n.adminConfigTmdbLanguage,
    'config.integration.tmdb.includeAdult' => l10n.adminConfigTmdbAdult,
    'config.integration.photoAi.enabled' => l10n.adminConfigPhotoAiEnabled,
    'config.integration.netease.enabled' => l10n.adminConfigNeteaseEnabled,
    'config.integration.qweather.projectId' =>
      l10n.adminConfigQWeatherProjectId,
    'config.integration.qweather.credentialId' =>
      l10n.adminConfigQWeatherCredentialId,
    'config.integration.qweather.privateKey' =>
      l10n.adminConfigQWeatherPrivateKey,
    _ => l10n.adminConfigUnknownItem,
  };
}

String _configDescription(AppLocalizations l10n, AdminConfigEntry entry) {
  final keyDescription =
      <String, String>{
        'storage.quota.default': l10n.adminConfigQuotaUnlimitedDescription,
        'storage.quota.default.gb': l10n.adminConfigQuotaUnlimitedDescription,
        'share.max-bytes': l10n.adminConfigQuotaUnlimitedDescription,
        'shared_space.max_bytes': l10n.adminConfigQuotaUnlimitedDescription,
        'media.tmdb.url': l10n.adminConfigEndpointDescription,
        'media.metadata-provider.tmdb.base-url':
            l10n.adminConfigEndpointDescription,
        'music.musicbrainz.url': l10n.adminConfigEndpointDescription,
        'music.metadata-provider.musicbrainz.base-url':
            l10n.adminConfigEndpointDescription,
        'weather.qweather.url': l10n.adminConfigEndpointDescription,
        'weather.qweather.base-url': l10n.adminConfigEndpointDescription,
        'music.netease.url': l10n.adminConfigEndpointDescription,
        'music.platform.netease.base-url': l10n.adminConfigEndpointDescription,
        'photo.ai.url': l10n.adminConfigEndpointDescription,
        'photo.ai.endpoint': l10n.adminConfigEndpointDescription,
        'reader.gbooks.url': l10n.adminConfigEndpointDescription,
        'reader.metadata-provider.google-books.base-url':
            l10n.adminConfigEndpointDescription,
        'reader.openlib.url': l10n.adminConfigEndpointDescription,
        'reader.metadata-provider.open-library.base-url':
            l10n.adminConfigEndpointDescription,
        'weather.location': l10n.adminConfigWeatherLocationDescription,
        'media.tmdb.lang': l10n.adminConfigTmdbLanguageDescription,
        'media.metadata-provider.tmdb.language':
            l10n.adminConfigTmdbLanguageDescription,
        'media.tmdb.adult': l10n.adminConfigTmdbAdultDescription,
        'media.metadata-provider.tmdb.include-adult':
            l10n.adminConfigTmdbAdultDescription,
        'media.tmdb.key': l10n.adminConfigCredentialDescription,
        'media.tmdb.token': l10n.adminConfigCredentialDescription,
        'media.metadata-provider.tmdb.api-key':
            l10n.adminConfigCredentialDescription,
        'media.metadata-provider.tmdb.access-token':
            l10n.adminConfigCredentialDescription,
        'reader.gbooks.key': l10n.adminConfigCredentialDescription,
        'reader.metadata-provider.google-books.api-key':
            l10n.adminConfigCredentialDescription,
        'weather.qweather.key': l10n.adminConfigCredentialDescription,
        'weather.qweather.private-key': l10n.adminConfigCredentialDescription,
        'weather.qweather.project':
            l10n.adminConfigProviderIdentifierDescription,
        'weather.qweather.project-id':
            l10n.adminConfigProviderIdentifierDescription,
        'weather.qweather.credential':
            l10n.adminConfigProviderIdentifierDescription,
        'weather.qweather.credential-id':
            l10n.adminConfigProviderIdentifierDescription,
        'media.tmdb.timeout': l10n.adminConfigInternalNumericDescription,
        'media.metadata-provider.tmdb.timeout-seconds':
            l10n.adminConfigInternalNumericDescription,
        'media.tmdb.limit': l10n.adminConfigInternalNumericDescription,
        'media.metadata-provider.tmdb.max-results':
            l10n.adminConfigInternalNumericDescription,
        'reader.gbooks.timeout': l10n.adminConfigInternalNumericDescription,
        'reader.metadata-provider.google-books.timeout-seconds':
            l10n.adminConfigInternalNumericDescription,
        'reader.gbooks.limit': l10n.adminConfigInternalNumericDescription,
        'reader.metadata-provider.google-books.max-results':
            l10n.adminConfigInternalNumericDescription,
        'photo.ai.timeout': l10n.adminConfigInternalNumericDescription,
        'photo.ai.timeout-seconds': l10n.adminConfigInternalNumericDescription,
        'media.tmdb.strategy': l10n.adminConfigTmdbStrategyDescription,
        'media.metadata-provider.tmdb.search-queries-strategy':
            l10n.adminConfigTmdbStrategyDescription,
        'media.import.enabled': l10n.adminConfigMediaAutoImportDescription,
        'media.auto-import.enabled': l10n.adminConfigMediaAutoImportDescription,
        'media.transcode.enabled': l10n.adminConfigMediaTranscodeDescription,
        'transcode.enabled': l10n.adminConfigMediaTranscodeDescription,
        'reader.import.enabled': l10n.adminConfigReaderAutoImportDescription,
        'reader.auto-import.enabled':
            l10n.adminConfigReaderAutoImportDescription,
        'music.import.enabled': l10n.adminConfigMusicAutoImportDescription,
        'music.auto-import.enabled': l10n.adminConfigMusicAutoImportDescription,
        'photo.geo.rate': l10n.adminConfigPhotoGeoRateDescription,
        'photo.geo.rate-limit-per-second':
            l10n.adminConfigPhotoGeoRateDescription,
        'upload.rate.enabled': l10n.adminConfigUploadRateDescription,
        'upload.bandwidth.enabled': l10n.adminConfigUploadRateDescription,
        'security.rate-limit': l10n.adminConfigSecurityRateLimitDescription,
        'rate-limit.default-limit':
            l10n.adminConfigSecurityRateLimitDescription,
        'music.musicbrainz.ua': l10n.adminConfigMusicBrainzUserAgentDescription,
        'music.metadata-provider.musicbrainz.user-agent':
            l10n.adminConfigMusicBrainzUserAgentDescription,
        'music.musicbrainz.cover-url': l10n.adminConfigEndpointDescription,
        'music.metadata-provider.musicbrainz.cover-base-url':
            l10n.adminConfigEndpointDescription,
        'music.netease.hosts': l10n.adminConfigHostSuffixesDescription,
        'music.platform.netease.playback-host-suffixes':
            l10n.adminConfigHostSuffixesDescription,
        'log-retention.enabled': l10n.adminConfigLogRetentionEnabledDescription,
        'log-retention.retention-days':
            l10n.adminConfigLogRetentionDaysDescription,
        'log-retention.scan-paths':
            l10n.adminConfigLogRetentionPathsDescription,
        'photo.geo.offline': l10n.adminConfigPhotoGeoOfflineDescription,
        'photo.geo.nominatim': l10n.adminConfigPhotoGeoNominatimDescription,
        'photo.geo.max-distance-km':
            l10n.adminConfigPhotoGeoMaxDistanceDescription,
        'photo.geo.import.batch-size':
            l10n.adminConfigPhotoGeoImportBatchSizeDescription,
        'photo.geo.import.auto': l10n.adminConfigPhotoGeoImportAutoDescription,
        'security.quarantine.retention-days':
            l10n.adminConfigQuarantineRetentionDaysDescription,
        'clamav.timeout-millis': l10n.adminConfigClamavTimeoutDescription,
        'auth.two-factor.required-roles':
            l10n.adminConfigTwoFactorRequiredRolesDescription,
        'backdrop.max-image-bytes':
            l10n.adminConfigBackdropMaxImageBytesDescription,
        'backdrop.max-video-bytes':
            l10n.adminConfigBackdropMaxVideoBytesDescription,
        'backdrop.max-assets-per-user':
            l10n.adminConfigBackdropMaxAssetsDescription,
        'backdrop.upload.rate-per-hour':
            l10n.adminConfigBackdropUploadRateDescription,
        'app.version.latest': l10n.adminConfigAppVersionLatestDescription,
        'app.version.release-notes-url':
            l10n.adminConfigAppVersionReleaseNotesDescription,
        'app.version.download-url':
            l10n.adminConfigAppVersionDownloadUrlDescription,
      }[entry.key];
  if (keyDescription != null) {
    return keyDescription;
  }
  return switch (entry.displayCode) {
    'config.media.autoImport' => l10n.adminConfigMediaAutoImportDescription,
    'config.photo.backup' => l10n.adminConfigPhotoBackupDescription,
    'config.storage.defaultQuota' => l10n.adminConfigDefaultQuotaDescription,
    'config.storage.warningPercent' => l10n.adminConfigQuotaWarningDescription,
    'config.storage.sharedSpace' => l10n.adminConfigSharedSpaceDescription,
    'config.storage.sharedSpaceLimit' =>
      l10n.adminConfigSharedSpaceLimitDescription,
    'config.storage.localMedia' => l10n.adminConfigLocalMediaDescription,
    'config.weather.enabled' => l10n.adminConfigWeatherDescription,
    'config.integration.tmdb.language' =>
      l10n.adminConfigTmdbLanguageDescription,
    'config.integration.tmdb.includeAdult' =>
      l10n.adminConfigTmdbAdultDescription,
    'config.integration.qweather.projectId' ||
    'config.integration.qweather.credentialId' =>
      l10n.adminConfigProviderIdentifierDescription,
    'config.integration.tmdb.apiKey' ||
    'config.integration.tmdb.accessToken' ||
    'config.integration.qweather.privateKey' =>
      l10n.adminConfigCredentialDescription,
    // 集成开关文案仅对布尔项成立；其余未映射项回退后端目录描述，
    // 避免字符串/数字配置被误标为“控制是否允许使用此集成服务”。
    _ =>
      entry.valueType == 'BOOLEAN' || entry.description.isEmpty
          ? l10n.adminConfigProviderToggleDescription
          : entry.description,
  };
}

String _configValueSummary(AppLocalizations l10n, AdminConfigEntry entry) {
  if (_isSensitiveConfigEntry(entry)) {
    return entry.sensitiveConfigured
        ? l10n.adminConfigSecretConfigured
        : l10n.adminConfigNeedsSetup;
  }
  if (entry.valueType == 'BOOLEAN') {
    return entry.value == 'true' ? l10n.adminEnabled : l10n.adminDisabled;
  }
  if (_isQuotaConfigEntry(entry) && _isUnlimitedQuota(entry)) {
    return l10n.adminConfigUnlimited;
  }
  if (entry.value.isEmpty) {
    return l10n.adminConfigNeedsSetup;
  }
  return l10n.adminConfigCurrentValue(
    _formatConfigValue(entry.key, entry.value),
  );
}

bool _isQuotaConfigEntry(AdminConfigEntry entry) {
  return entry.key == 'storage.quota.default' ||
      entry.key == 'storage.quota.default.gb' ||
      entry.key == 'share.max-bytes' ||
      entry.key == 'shared_space.max_bytes';
}

bool _isUnlimitedQuota(AdminConfigEntry entry) {
  final value = double.tryParse(entry.value);
  return value != null && value <= 0;
}

bool _isSensitiveConfigEntry(AdminConfigEntry entry) {
  const sensitiveDisplayCodes = {
    'config.integration.tmdb.apiKey',
    'config.integration.tmdb.accessToken',
    'config.integration.qweather.privateKey',
  };
  const sensitiveKeys = {
    'media.tmdb.key',
    'media.tmdb.token',
    'reader.gbooks.key',
    'weather.qweather.key',
    'media.metadata-provider.tmdb.api-key',
    'media.metadata-provider.tmdb.access-token',
    'reader.metadata-provider.google-books.api-key',
    'weather.qweather.private-key',
  };
  return sensitiveDisplayCodes.contains(entry.displayCode) ||
      sensitiveKeys.contains(entry.key);
}
