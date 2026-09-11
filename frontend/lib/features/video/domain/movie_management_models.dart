import 'package:omninest/features/video/domain/movie_model_json.dart';

class MediaPage<T> {
  const MediaPage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  });

  final List<T> items;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;

  static MediaPage<T> fromJson<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) decode,
  ) {
    final rawItems = json['items'];
    return MediaPage<T>(
      items:
          rawItems is List
              ? rawItems.whereType<Map<String, dynamic>>().map(decode).toList()
              : const [],
      page: MovieJson.asInt(json['page']),
      size: MovieJson.asInt(json['size']),
      totalElements: MovieJson.asInt(json['totalElements']),
      totalPages: MovieJson.asInt(json['totalPages']),
    );
  }
}

class VideoStorageLocation {
  const VideoStorageLocation({
    required this.id,
    required this.name,
    required this.providerType,
    required this.mountKey,
    required this.relativeRoot,
    required this.scopeType,
    required this.enabled,
    required this.healthStatus,
    this.rootName = '',
  });

  factory VideoStorageLocation.fromJson(Map<String, dynamic> json) {
    return VideoStorageLocation(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      providerType: json['providerType']?.toString() ?? '',
      mountKey: json['mountKey']?.toString() ?? '',
      relativeRoot: json['relativeRoot']?.toString() ?? '.',
      scopeType: json['scopeType']?.toString() ?? '',
      enabled: json['enabled'] == true,
      healthStatus: json['healthStatus']?.toString() ?? 'UNAVAILABLE',
      rootName: json['rootName']?.toString() ?? '',
    );
  }

  final String id;
  final String name;
  final String providerType;
  final String mountKey;
  final String relativeRoot;
  final String scopeType;
  final bool enabled;
  final String healthStatus;
  final String rootName;

  bool get available => enabled && healthStatus == 'AVAILABLE';
}

class VideoStorageDirectory {
  const VideoStorageDirectory({
    required this.nodeId,
    required this.name,
    required this.relativePath,
    required this.hasChildren,
  });

  factory VideoStorageDirectory.fromJson(Map<String, dynamic> json) {
    return VideoStorageDirectory(
      nodeId: json['nodeId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      relativePath: json['relativePath']?.toString() ?? '.',
      hasChildren: json['hasChildren'] == true,
    );
  }

  final String nodeId;
  final String name;
  final String relativePath;
  final bool hasChildren;
}

class VideoTrustedMount {
  const VideoTrustedMount({
    required this.mountKey,
    required this.displayName,
    required this.available,
  });

  factory VideoTrustedMount.fromJson(Map<String, dynamic> json) {
    return VideoTrustedMount(
      mountKey: json['mountKey']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      available: json['available'] == true,
    );
  }

  final String mountKey;
  final String displayName;
  final bool available;
}

enum VideoLibraryType {
  movie('MOVIE'),
  tvSeries('TV_SERIES'),
  anime('ANIME'),
  root('ROOT');

  const VideoLibraryType(this.apiValue);

  final String apiValue;

  static VideoLibraryType fromApi(String? value) {
    return values.firstWhere(
      (type) => type.apiValue == value,
      orElse: () => VideoLibraryType.movie,
    );
  }
}

enum MediaLibraryVisibility {
  private('PRIVATE'),
  selectedUsers('SELECTED_USERS'),
  allMembers('ALL_MEMBERS');

  const MediaLibraryVisibility(this.apiValue);

  final String apiValue;

  static MediaLibraryVisibility fromApi(String? value) {
    return values.firstWhere(
      (visibility) => visibility.apiValue == value,
      orElse: () => MediaLibraryVisibility.private,
    );
  }
}

class VideoLibrarySource {
  const VideoLibrarySource({
    required this.id,
    required this.name,
    required this.storageLocationId,
    required this.relativeRoot,
    required this.libraryType,
    required this.importPolicy,
    required this.visibility,
    required this.enabled,
    required this.scanStatus,
    required this.healthStatus,
    required this.lastScannedCount,
    required this.lastCreatedCount,
    required this.lastCandidateCount,
    required this.lastMissingCount,
    required this.version,
    this.lastScannedAt,
    this.lastSuccessfulScanAt,
    this.lastErrorCode,
  });

  factory VideoLibrarySource.fromJson(Map<String, dynamic> json) {
    return VideoLibrarySource(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      storageLocationId: json['storageLocationId']?.toString() ?? '',
      relativeRoot: json['relativeRoot']?.toString() ?? '.',
      libraryType: VideoLibraryType.fromApi(json['libraryType']?.toString()),
      importPolicy: json['importPolicy']?.toString() ?? 'MANUAL_REVIEW',
      visibility: MediaLibraryVisibility.fromApi(
        json['visibilityType']?.toString(),
      ),
      enabled: json['enabled'] == true,
      scanStatus: json['scanStatus']?.toString() ?? 'NEVER_SCANNED',
      healthStatus: json['healthStatus']?.toString() ?? 'AVAILABLE',
      lastScannedAt:
          DateTime.tryParse(json['lastScannedAt']?.toString() ?? '')?.toLocal(),
      lastErrorCode: json['lastErrorCode']?.toString(),
      lastSuccessfulScanAt:
          DateTime.tryParse(
            json['lastSuccessfulScanAt']?.toString() ?? '',
          )?.toLocal(),
      lastScannedCount: MovieJson.asInt(json['lastScannedCount']),
      lastCreatedCount: MovieJson.asInt(json['lastCreatedCount']),
      lastCandidateCount: MovieJson.asInt(json['lastCandidateCount']),
      lastMissingCount: MovieJson.asInt(json['lastMissingCount']),
      version: MovieJson.asInt(json['version']),
    );
  }

  final String id;
  final String name;
  final String storageLocationId;
  final String relativeRoot;
  final VideoLibraryType libraryType;
  final String importPolicy;
  final MediaLibraryVisibility visibility;
  final bool enabled;
  final String scanStatus;
  final String healthStatus;
  final DateTime? lastScannedAt;
  final DateTime? lastSuccessfulScanAt;
  final String? lastErrorCode;
  final int lastScannedCount;
  final int lastCreatedCount;
  final int lastCandidateCount;
  final int lastMissingCount;
  final int version;
}

class MediaLibraryAccessSettings {
  const MediaLibraryAccessSettings({
    required this.librarySourceId,
    required this.visibility,
    required this.selectedUserIds,
    required this.version,
  });

  factory MediaLibraryAccessSettings.fromJson(Map<String, dynamic> json) {
    final rawUserIds = json['selectedUserIds'];
    return MediaLibraryAccessSettings(
      librarySourceId: json['librarySourceId']?.toString() ?? '',
      visibility: MediaLibraryVisibility.fromApi(
        json['visibilityType']?.toString(),
      ),
      selectedUserIds: Set<String>.unmodifiable(
        rawUserIds is Iterable
            ? rawUserIds.map((item) => item.toString())
            : const <String>[],
      ),
      version: MovieJson.asInt(json['version']),
    );
  }

  final String librarySourceId;
  final MediaLibraryVisibility visibility;
  final Set<String> selectedUserIds;
  final int version;
}

class MediaLibraryUserCandidate {
  const MediaLibraryUserCandidate({
    required this.id,
    required this.username,
    required this.displayName,
    required this.status,
  });

  factory MediaLibraryUserCandidate.fromJson(Map<String, dynamic> json) {
    return MediaLibraryUserCandidate(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
    );
  }

  final String id;
  final String username;
  final String displayName;
  final String status;
}

class MediaScanRun {
  const MediaScanRun({
    required this.id,
    required this.librarySourceId,
    required this.generation,
    required this.selectionRevision,
    required this.status,
    required this.phase,
    required this.discoveredCount,
    required this.candidateCount,
    required this.existingCount,
    required this.conflictCount,
    required this.unmatchedCount,
    required this.missingCount,
    required this.selectedCount,
    required this.appliedCount,
    required this.failedCount,
  });

  factory MediaScanRun.fromJson(Map<String, dynamic> json) {
    return MediaScanRun(
      id: json['id']?.toString() ?? '',
      librarySourceId: json['librarySourceId']?.toString() ?? '',
      generation: MovieJson.asInt(json['generation']),
      selectionRevision: MovieJson.asInt(json['selectionRevision']),
      status: json['status']?.toString() ?? 'QUEUED',
      phase: json['phase']?.toString() ?? 'DISCOVERY',
      discoveredCount: MovieJson.asInt(json['discoveredCount']),
      candidateCount: MovieJson.asInt(json['candidateCount']),
      existingCount: MovieJson.asInt(json['existingCount']),
      conflictCount: MovieJson.asInt(json['conflictCount']),
      unmatchedCount: MovieJson.asInt(json['unmatchedCount']),
      missingCount: MovieJson.asInt(json['missingCount']),
      selectedCount: MovieJson.asInt(json['selectedCount']),
      appliedCount: MovieJson.asInt(json['appliedCount']),
      failedCount: MovieJson.asInt(json['failedCount']),
    );
  }

  final String id;
  final String librarySourceId;
  final int generation;
  final int selectionRevision;
  final String status;
  final String phase;
  final int discoveredCount;
  final int candidateCount;
  final int existingCount;
  final int conflictCount;
  final int unmatchedCount;
  final int missingCount;
  final int selectedCount;
  final int appliedCount;
  final int failedCount;

  bool get active =>
      const {'QUEUED', 'DISCOVERING', 'APPLYING'}.contains(status);
  bool get reviewable => const {'READY', 'PAUSED', 'PARTIAL'}.contains(status);
}

class MediaScanTreeNode {
  const MediaScanTreeNode({
    required this.nodeId,
    required this.nodeType,
    required this.title,
    required this.hasChildren,
    required this.childCount,
    required this.candidateCount,
    required this.selectedCount,
    required this.issueCount,
    required this.selectionState,
    this.subtitle,
    this.matchStatus,
    this.applyStatus,
    this.reasonCode,
    this.candidateId,
    this.sizeBytes,
  });

  factory MediaScanTreeNode.fromJson(Map<String, dynamic> json) {
    return MediaScanTreeNode(
      nodeId: json['nodeId']?.toString() ?? '',
      nodeType: json['nodeType']?.toString() ?? 'FILE',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString(),
      hasChildren: json['hasChildren'] == true,
      childCount: MovieJson.asInt(json['childCount']),
      candidateCount: MovieJson.asInt(json['candidateCount']),
      selectedCount: MovieJson.asInt(json['selectedCount']),
      issueCount: MovieJson.asInt(json['issueCount']),
      selectionState: json['selectionState']?.toString() ?? 'NONE',
      matchStatus: json['matchStatus']?.toString(),
      applyStatus: json['applyStatus']?.toString(),
      reasonCode: json['reasonCode']?.toString(),
      candidateId: json['candidateId']?.toString(),
      sizeBytes:
          json['sizeBytes'] == null ? null : MovieJson.asInt(json['sizeBytes']),
    );
  }

  final String nodeId;
  final String nodeType;
  final String title;
  final String? subtitle;
  final bool hasChildren;
  final int childCount;
  final int candidateCount;
  final int selectedCount;
  final int issueCount;
  final String selectionState;
  final String? matchStatus;
  final String? applyStatus;
  final String? reasonCode;
  final String? candidateId;
  final int? sizeBytes;
}

class MediaSelectionSummary {
  const MediaSelectionSummary({
    required this.scanRunId,
    required this.revision,
    required this.candidateCount,
    required this.selectedCount,
    required this.existingCount,
    required this.unmatchedCount,
    required this.failedCount,
  });

  factory MediaSelectionSummary.fromJson(Map<String, dynamic> json) {
    return MediaSelectionSummary(
      scanRunId: json['scanRunId']?.toString() ?? '',
      revision: MovieJson.asInt(json['revision']),
      candidateCount: MovieJson.asInt(json['candidateCount']),
      selectedCount: MovieJson.asInt(json['selectedCount']),
      existingCount: MovieJson.asInt(json['existingCount']),
      unmatchedCount: MovieJson.asInt(json['unmatchedCount']),
      failedCount: MovieJson.asInt(json['failedCount']),
    );
  }

  final String scanRunId;
  final int revision;
  final int candidateCount;
  final int selectedCount;
  final int existingCount;
  final int unmatchedCount;
  final int failedCount;
}

class MovieTask {
  const MovieTask({
    required this.id,
    required this.taskType,
    required this.status,
    required this.progress,
    this.routingKey,
    this.errorSummary,
    this.updatedAt,
  });

  final String id;
  final String taskType;
  final String status;
  final int progress;
  final String? routingKey;
  final String? errorSummary;
  final DateTime? updatedAt;

  factory MovieTask.fromJson(Map<String, dynamic> json) {
    return MovieTask(
      id: json['id']?.toString() ?? '',
      taskType: json['taskType']?.toString() ?? '',
      status: json['status']?.toString() ?? 'QUEUED',
      progress: MovieJson.asInt(json['progress']),
      routingKey: json['routingKey']?.toString(),
      errorSummary: json['errorSummary']?.toString(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toLocal(),
    );
  }
}

class ScrapeTask {
  const ScrapeTask({
    required this.taskId,
    required this.status,
    required this.message,
  });

  final String taskId;
  final String status;
  final String message;

  factory ScrapeTask.fromJson(Map<String, dynamic> json) {
    return ScrapeTask(
      taskId: json['taskId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'QUEUED',
      message: json['message']?.toString() ?? '',
    );
  }
}

class NfoExport {
  const NfoExport({
    required this.videoItemId,
    required this.status,
    required this.exportPath,
    required this.content,
    this.id,
    this.exportedAt,
  });

  final String? id;
  final String videoItemId;
  final String status;
  final String exportPath;
  final DateTime? exportedAt;
  final String content;

  factory NfoExport.fromJson(Map<String, dynamic> json) {
    return NfoExport(
      id: json['id']?.toString(),
      videoItemId: json['videoItemId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'DISABLED',
      exportPath: json['exportPath']?.toString() ?? '',
      exportedAt:
          DateTime.tryParse(json['exportedAt']?.toString() ?? '')?.toLocal(),
      content: json['content']?.toString() ?? '',
    );
  }
}

class UploadSession {
  const UploadSession({
    required this.id,
    required this.uploadId,
    required this.fileName,
    required this.status,
    this.uploadUrl,
  });

  final String id;
  final String uploadId;
  final String fileName;
  final String status;
  final String? uploadUrl;

  factory UploadSession.fromJson(Map<String, dynamic> json) {
    return UploadSession(
      id: json['id']?.toString() ?? '',
      uploadId: json['uploadId']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      status: json['status']?.toString() ?? 'CREATED',
      uploadUrl: json['uploadUrl']?.toString(),
    );
  }
}

class FileNodeResult {
  const FileNodeResult({required this.id, required this.name});

  final String id;
  final String name;

  factory FileNodeResult.fromJson(Map<String, dynamic> json) {
    return FileNodeResult(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }
}

class VideoScrapeCandidate {
  const VideoScrapeCandidate({
    required this.provider,
    required this.externalId,
    required this.title,
    this.originalTitle,
    this.releaseDate,
    this.year,
    this.overview,
    this.posterUrl,
    this.backdropUrl,
    this.runtimeMinutes,
    this.voteAverage,
    this.imdbId,
    this.genres = const [],
    this.voteCount,
    this.contentRating,
    this.tagline,
    this.popularity,
    this.originalLanguage,
    this.screenshotUrls = const [],
  });

  factory VideoScrapeCandidate.fromJson(Map<String, dynamic> json) {
    return VideoScrapeCandidate(
      provider: json['provider']?.toString() ?? '',
      externalId: json['externalId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      originalTitle: json['originalTitle']?.toString(),
      releaseDate: DateTime.tryParse(json['releaseDate']?.toString() ?? ''),
      year: MovieJson.nullableInt(json['year']),
      overview: json['overview']?.toString(),
      posterUrl: json['posterUrl']?.toString(),
      backdropUrl: json['backdropUrl']?.toString(),
      runtimeMinutes: MovieJson.nullableInt(json['runtimeMinutes']),
      voteAverage: MovieJson.nullableDouble(json['voteAverage']),
      imdbId: json['imdbId']?.toString(),
      genres: MovieJson.stringList(json['genres']),
      voteCount: MovieJson.nullableInt(json['voteCount']),
      contentRating: json['contentRating']?.toString(),
      tagline: json['tagline']?.toString(),
      popularity: MovieJson.nullableDouble(json['popularity']),
      originalLanguage: json['originalLanguage']?.toString(),
      screenshotUrls: MovieJson.stringList(json['screenshotUrls']),
    );
  }

  final String provider;
  final String externalId;
  final String title;
  final String? originalTitle;
  final DateTime? releaseDate;
  final int? year;
  final String? overview;
  final String? posterUrl;
  final String? backdropUrl;
  final int? runtimeMinutes;
  final double? voteAverage;
  final String? imdbId;
  final List<String> genres;
  final int? voteCount;
  final String? contentRating;
  final String? tagline;
  final double? popularity;
  final String? originalLanguage;
  final List<String> screenshotUrls;
}
