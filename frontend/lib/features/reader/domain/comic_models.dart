/// 漫画清单 — 描述一个漫画作品的完整结构。
class ComicManifest {
  const ComicManifest({
    required this.itemId,
    required this.sources,
    required this.catalog,
    required this.pages,
    this.manifestVersion = 1,
    this.importStatus = 'READY',
    this.readingDirection,
    this.parseTask,
  });

  final String itemId;
  final List<ComicSource> sources;
  final List<ComicCatalogNode> catalog;
  final List<ComicPage> pages;
  final int manifestVersion;
  final String importStatus;
  final String? readingDirection;
  final ComicParseTask? parseTask;

  /// 按 catalogNodeId 分组的页面。
  Map<String?, List<ComicPage>> get pagesByCatalog {
    final map = <String?, List<ComicPage>>{};
    for (final page in pages) {
      map.putIfAbsent(page.catalogNodeId, () => []).add(page);
    }
    return map;
  }

  /// 总页数。
  int get totalPages => pages.length;

  factory ComicManifest.fromJson(Map<String, dynamic> json) {
    return ComicManifest(
      itemId: json['itemId']?.toString() ?? '',
      sources:
          (json['sources'] as List?)
              ?.map((e) => ComicSource.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      catalog:
          (json['catalog'] as List?)
              ?.map((e) => ComicCatalogNode.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      pages:
          (json['pages'] as List?)
              ?.map((e) => ComicPage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      manifestVersion: json['manifestVersion'] as int? ?? 1,
      importStatus: json['importStatus']?.toString() ?? 'READY',
      readingDirection: json['readingDirection']?.toString(),
      parseTask:
          json['parseTask'] is Map<String, dynamic>
              ? ComicParseTask.fromJson(
                json['parseTask'] as Map<String, dynamic>,
              )
              : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'sources': sources.map((e) => e.toJson()).toList(),
    'catalog': catalog.map((e) => e.toJson()).toList(),
    'pages': pages.map((e) => e.toJson()).toList(),
    'manifestVersion': manifestVersion,
    'importStatus': importStatus,
    'readingDirection': readingDirection,
    'parseTask': parseTask?.toJson(),
  };
}

/// 漫画后台解析任务状态。
class ComicParseTask {
  const ComicParseTask({
    required this.id,
    required this.status,
    required this.progress,
    this.errorMessage,
    this.updatedAt,
  });

  final String id;
  final String status;
  final int progress;
  final String? errorMessage;
  final DateTime? updatedAt;

  factory ComicParseTask.fromJson(Map<String, dynamic> json) {
    return ComicParseTask(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'QUEUED',
      progress: ((json['progress'] as num?)?.toInt() ?? 0).clamp(0, 100),
      errorMessage: json['errorMessage']?.toString(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status,
    'progress': progress,
    'errorMessage': errorMessage,
    'updatedAt': updatedAt?.toIso8601String(),
  };
}

/// 漫画来源文件。
class ComicSource {
  const ComicSource({
    required this.id,
    required this.fileFormat,
    required this.sourceName,
    this.fileNodeId,
    this.sourceSortKey,
    this.readingDirection,
    this.status = 'READY',
    this.errorCode,
    this.errorMessage,
    this.retryCount = 0,
    this.seasonNo,
    this.volumeNo,
    this.chapterStart,
    this.chapterEnd,
    this.extraOrder,
    this.pageCount = 0,
  });

  final String id;
  final String? fileNodeId;
  // CBZ, ZIP, EPUB
  final String fileFormat;
  final String sourceName;
  final String? sourceSortKey;
  final String? readingDirection;
  final String status;
  final String? errorCode;
  final String? errorMessage;
  final int retryCount;
  final int? seasonNo;
  final int? volumeNo;
  final int? chapterStart;
  final int? chapterEnd;
  final int? extraOrder;
  final int pageCount;

  factory ComicSource.fromJson(Map<String, dynamic> json) => ComicSource(
    id: json['id']?.toString() ?? '',
    fileNodeId: json['fileNodeId']?.toString(),
    fileFormat: json['fileFormat']?.toString() ?? '',
    sourceName: json['sourceName']?.toString() ?? '',
    sourceSortKey: json['sourceSortKey']?.toString(),
    readingDirection: json['readingDirection']?.toString(),
    status: json['status']?.toString() ?? 'READY',
    errorCode: json['errorCode']?.toString(),
    errorMessage: json['errorMessage']?.toString(),
    retryCount: json['retryCount'] as int? ?? 0,
    seasonNo: json['seasonNo'] as int?,
    volumeNo: json['volumeNo'] as int?,
    chapterStart: json['chapterStart'] as int?,
    chapterEnd: json['chapterEnd'] as int?,
    extraOrder: json['extraOrder'] as int?,
    pageCount: json['pageCount'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileNodeId': fileNodeId,
    'fileFormat': fileFormat,
    'sourceName': sourceName,
    'sourceSortKey': sourceSortKey,
    'readingDirection': readingDirection,
    'status': status,
    'errorCode': errorCode,
    'errorMessage': errorMessage,
    'retryCount': retryCount,
    'seasonNo': seasonNo,
    'volumeNo': volumeNo,
    'chapterStart': chapterStart,
    'chapterEnd': chapterEnd,
    'extraOrder': extraOrder,
    'pageCount': pageCount,
  };
}

/// 漫画目录节点（季/卷/话/合集/番外）。
class ComicCatalogNode {
  const ComicCatalogNode({
    required this.id,
    required this.nodeType,
    required this.title,
    this.parentId,
    this.sourceId,
    this.sortOrder = 0,
    this.pageCount = 0,
    this.catalogKey,
    this.pageStartIndex,
    this.pageEndIndex,
  });

  final String id;
  final String? parentId;
  // 来源文件 ID（用于多源区分）
  final String? sourceId;
  // ROOT, SEASON, VOLUME, CHAPTER, COLLECTION, EXTRA
  final String nodeType;
  final String title;
  final int sortOrder;
  final int pageCount;
  final String? catalogKey;
  final int? pageStartIndex;
  final int? pageEndIndex;

  bool get isRoot => nodeType == 'ROOT';
  bool get isChapter => nodeType == 'CHAPTER';

  factory ComicCatalogNode.fromJson(Map<String, dynamic> json) =>
      ComicCatalogNode(
        id: json['id']?.toString() ?? '',
        parentId: json['parentId']?.toString(),
        sourceId: json['sourceId']?.toString(),
        nodeType: json['nodeType']?.toString() ?? 'CHAPTER',
        title: json['title']?.toString() ?? '',
        sortOrder: json['sortOrder'] as int? ?? 0,
        pageCount: json['pageCount'] as int? ?? 0,
        catalogKey: json['catalogKey']?.toString(),
        pageStartIndex: json['pageStartIndex'] as int?,
        pageEndIndex: json['pageEndIndex'] as int?,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'parentId': parentId,
    'sourceId': sourceId,
    'nodeType': nodeType,
    'title': title,
    'sortOrder': sortOrder,
    'pageCount': pageCount,
    'catalogKey': catalogKey,
    'pageStartIndex': pageStartIndex,
    'pageEndIndex': pageEndIndex,
  };
}

/// 漫画页面。
class ComicPage {
  const ComicPage({
    required this.id,
    required this.sourceId,
    required this.pageIndex,
    required this.sourcePath,
    this.catalogNodeId,
    this.catalogKey,
    this.sourcePageIndex = 0,
    this.width,
    this.height,
    this.fingerprint,
    this.entryIndex,
    this.mimeType,
    this.byteSize,
  });

  final String id;
  final String sourceId;
  final String? catalogNodeId;
  final String? catalogKey;
  final int pageIndex;
  final int sourcePageIndex;
  final String sourcePath;
  final int? width;
  final int? height;
  final String? fingerprint;
  final int? entryIndex;
  final String? mimeType;
  final int? byteSize;

  factory ComicPage.fromJson(Map<String, dynamic> json) => ComicPage(
    id: json['id']?.toString() ?? '',
    sourceId: json['sourceId']?.toString() ?? '',
    catalogNodeId: json['catalogNodeId']?.toString(),
    catalogKey: json['catalogKey']?.toString(),
    pageIndex: json['pageIndex'] as int? ?? 0,
    sourcePageIndex: json['sourcePageIndex'] as int? ?? 0,
    sourcePath: json['sourcePath']?.toString() ?? '',
    width: json['width'] as int?,
    height: json['height'] as int?,
    fingerprint: json['fingerprint']?.toString(),
    entryIndex: json['entryIndex'] as int?,
    mimeType: json['mimeType']?.toString(),
    byteSize: json['byteSize'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'catalogNodeId': catalogNodeId,
    'catalogKey': catalogKey,
    'pageIndex': pageIndex,
    'sourcePageIndex': sourcePageIndex,
    'sourcePath': sourcePath,
    'width': width,
    'height': height,
    'fingerprint': fingerprint,
    'entryIndex': entryIndex,
    'mimeType': mimeType,
    'byteSize': byteSize,
  };
}

/// 漫画阅读进度锚点。
class ComicProgressAnchor {
  const ComicProgressAnchor({
    required this.itemId,
    this.pageId,
    this.pageIndex,
    this.pageFingerprint,
    this.sourceId,
    this.sourcePageIndex,
    this.catalogKey,
    this.catalogNodeId,
    this.intraPageOffset = 0.0,
    this.manifestVersion = 1,
  });

  final String itemId;
  final String? pageId;
  final int? pageIndex;
  final String? pageFingerprint;
  final String? sourceId;
  final int? sourcePageIndex;
  final String? catalogKey;
  final String? catalogNodeId;
  // 长条图页内偏移（0.0-1.0）
  final double intraPageOffset;
  final int manifestVersion;

  factory ComicProgressAnchor.fromJson(Map<String, dynamic> json) =>
      ComicProgressAnchor(
        itemId: json['itemId']?.toString() ?? '',
        pageId: json['pageId']?.toString(),
        pageIndex: json['pageIndex'] as int?,
        pageFingerprint: json['pageFingerprint']?.toString(),
        sourceId: json['sourceId']?.toString(),
        sourcePageIndex: json['sourcePageIndex'] as int?,
        catalogKey: json['catalogKey']?.toString(),
        catalogNodeId: json['catalogNodeId']?.toString(),
        intraPageOffset: (json['intraPageOffset'] as num?)?.toDouble() ?? 0.0,
        manifestVersion: json['manifestVersion'] as int? ?? 1,
      );

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'pageId': pageId,
    'pageIndex': pageIndex,
    'pageFingerprint': pageFingerprint,
    'sourceId': sourceId,
    'sourcePageIndex': sourcePageIndex,
    'catalogKey': catalogKey,
    'catalogNodeId': catalogNodeId,
    'intraPageOffset': intraPageOffset,
    'manifestVersion': manifestVersion,
  };
}
