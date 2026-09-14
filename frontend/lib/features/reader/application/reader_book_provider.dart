import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/features/reader/application/reader_cache_providers.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_parsed_book_cache.dart';
import 'package:omninest/features/reader/data/cached_book_handle.dart';
import 'package:omninest/features/reader/data/epub_parser_service.dart';
import 'package:omninest/features/reader/data/local_book_cache.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/data/reader_content_preprocessor.dart';
import 'package:omninest/features/reader/data/reader_image_cache.dart';
import 'package:omninest/features/reader/data/reader_local_storage.dart';
import 'package:omninest/features/reader/data/txt_parser_service.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/domain/reader_status_constants.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 阅读页面持有的源文件句柄。
///
/// Web 使用受限内存字节，原生平台按需解密到会话临时文件。
final cachedBookHandleProvider = FutureProvider.autoDispose
    .family<CachedBookHandle, String>((ref, itemId) async {
      final api = ref.watch(readerApiProvider);
      final cache = ref.watch(localBookCacheProvider);
      final handle = await cache.ensureCachedHandle(
        itemId,
        webDownloader: () => api.downloadFileBytes(itemId),
        nativeDownloader: (path) => api.downloadFileToPath(itemId, path),
      );
      ref.onDispose(() {
        unawaited(handle.close());
      });
      return handle;
    });

/// 阅读条目解析进度：按内容类型轮询文本或漫画清单中的后台任务。
///
/// 使用 Stream 以固定间隔多次发出进度，书架卡片不依赖全局导入监控器
/// 的 invalidate 也能前进；终态、失败或达到最大轮询次数后结束，
/// 卡片不可见时由 autoDispose 取消订阅停止轮询。
final textParseProgressProvider = StreamProvider.autoDispose.family<
  ({int progress, bool finished, String? errorMessage}),
  String
>((ref, itemId) async* {
  final api = ref.watch(readerApiProvider);
  final detail = await ref.watch(readerItemDetailProvider(itemId).future);
  final isComic = detail.item.isComic;
  const pollInterval = Duration(seconds: 3);
  const maximumPolls = 100;
  for (var attempt = 0; attempt < maximumPolls; attempt++) {
    if (!ref.mounted) {
      return;
    }
    ({int progress, bool finished, String? errorMessage}) result;
    try {
      result = await _queryParseProgress(api, itemId, isComic);
    } on Object catch (error) {
      if (kDebugMode) {
        readerDebugLog('Reader parse progress poll failed for $itemId: $error');
      }
      result = (progress: 0, finished: false, errorMessage: null);
    }
    yield result;
    if (result.finished) {
      return;
    }
    await Future<void>.delayed(pollInterval);
  }
});

Future<({int progress, bool finished, String? errorMessage})>
_queryParseProgress(ReaderApi api, String itemId, bool isComic) async {
  if (isComic) {
    final manifest = await api.getComicManifest(itemId);
    final failedSource =
        manifest.sources
            .where((source) => source.status == ReaderSourceStatus.failed)
            .firstOrNull;
    final finished =
        manifest.importStatus != ReaderImportStatus.pending &&
        manifest.importStatus != ReaderImportStatus.parsing;
    return (
      progress: manifest.parseTask?.progress ?? 0,
      finished: finished,
      errorMessage:
          manifest.parseTask?.errorMessage ?? failedSource?.errorMessage,
    );
  }
  final manifest = await api.getTextManifest(itemId);
  final parseTask = manifest.parseTask;
  final finished = manifest.importStatus != ReaderImportStatus.parsing;
  return (
    progress: parseTask?.progress ?? 0,
    finished: finished,
    errorMessage: manifest.errorMessage,
  );
}

/// 书架解析任务监控器。请求严格串行，页面退出后停止客户端监控但不取消后端任务。
final readerImportMonitorProvider = Provider.autoDispose<void>((ref) {
  final monitor = _ReaderImportMonitor(ref);
  ref.listen<AsyncValue<ReaderCenterState>>(
    readerCenterControllerProvider,
    (_, next) => monitor.sync(next.asData?.value),
    fireImmediately: true,
  );
  ref.onDispose(monitor.dispose);
});

class _ReaderImportMonitor {
  _ReaderImportMonitor(this._ref);

  static const _maximumDuration = Duration(minutes: 30);
  static const _maximumConsecutiveFailures = 8;
  final Ref _ref;
  Set<String> _importingIds = const {};
  int _generation = 0;
  bool _running = false;

  void sync(ReaderCenterState? state) {
    final nextIds =
        state?.items
            .where((item) => item.isParsing)
            .map((item) => item.id)
            .toSet();
    _importingIds = nextIds ?? const {};
    if (_importingIds.isEmpty) {
      _generation++;
      _running = false;
      return;
    }
    if (_running) {
      return;
    }
    _running = true;
    final generation = ++_generation;
    unawaited(_run(generation));
  }

  Future<void> _run(int generation) async {
    var consecutiveFailures = 0;
    final startedAt = DateTime.now();
    try {
      while (_ref.mounted && generation == _generation) {
        if (DateTime.now().difference(startedAt) >= _maximumDuration) {
          readerDebugLog('Reader import monitor reached its total timeout');
          return;
        }
        final seconds = switch (consecutiveFailures) {
          0 => 3,
          1 => 3,
          2 => 6,
          _ => 12,
        };
        await Future<void>.delayed(Duration(seconds: seconds));
        if (!_ref.mounted || generation != _generation) {
          return;
        }
        try {
          await _ref
              .read(readerCenterControllerProvider.notifier)
              .refreshForRealtime();
          if (!_ref.mounted || generation != _generation) {
            return;
          }
          consecutiveFailures = 0;
          for (final itemId in _importingIds) {
            _ref.invalidate(textParseProgressProvider(itemId));
          }
        } on Object catch (error) {
          consecutiveFailures++;
          readerDebugLog(
            'Reader import status refresh failed '
            '($consecutiveFailures/$_maximumConsecutiveFailures): $error',
          );
          if (_isTaskNotFound(error) ||
              consecutiveFailures >= _maximumConsecutiveFailures) {
            return;
          }
        }
      }
    } finally {
      if (generation == _generation) {
        _running = false;
      }
    }
  }

  bool _isTaskNotFound(Object error) {
    if (error is! AppException) {
      return false;
    }
    final code = error.code.toUpperCase();
    return code == 'NOT_FOUND' || code == 'TASK_NOT_FOUND' || code == '404';
  }

  void dispose() {
    _generation++;
    _running = false;
  }
}

/// EPUB 解析服务实例，随阅读页面释放解压后的归档。
final epubParserServiceProvider = Provider.autoDispose
    .family<EpubParserService, String>((ref, itemId) {
      final service = EpubParserService();
      ref.onDispose(service.releaseArchive);
      return service;
    });

/// TXT 解析服务实例
final txtParserServiceProvider = Provider<TxtParserService>((ref) {
  return TxtParserService();
});

/// 解析后的书籍元数据 provider
///
/// 缓存策略（三层）：
/// 1. 内存 LRU（最快，会话级）
/// 2. SQLite 持久化（跨会话，秒开已读过的书）
/// 3. 文件缓存 + 网络下载（仅首次）
final parsedBookProvider = FutureProvider.autoDispose.family<
  ParsedBook,
  String
>((ref, itemId) async {
  final keepAliveLink = ref.keepAlive();
  try {
    final memoryCache = ref.watch(readerParsedBookCacheProvider);
    final detail = await ref.watch(readerItemDetailProvider(itemId).future);
    final itemType = detail.item.itemType;

    if (detail.item.contentKind == 'COMIC' ||
        itemType == 'CBZ' ||
        itemType == 'ZIP') {
      final book = const ParsedBook(chapters: []);
      memoryCache.write(itemId, book);
      if (kDebugMode) {
        readerDebugLog(
          'parsedBookProvider: comic item uses backend manifest for $itemId',
        );
      }
      return book;
    }

    // ── Layer 1: 内存 LRU 命中 ──
    final memoryBook = memoryCache.read(itemId);
    if (memoryBook != null && memoryBook.chapters.isNotEmpty) {
      if (kDebugMode) {
        readerDebugLog('parsedBookProvider: memory cache hit for $itemId');
      }
      return memoryBook;
    }
    if (memoryBook != null) {
      memoryCache.remove(itemId);
    }

    // ── Layer 2: SQLite 持久化缓存命中 ──
    final localStorage = ref.read(readerLocalStorageProvider);
    var cachedMeta = await localStorage.loadBookMeta(itemId);
    // 服务端重解析会更新条目 updatedAt；版本不符说明章节偏移/目录可能
    // 已变化，元数据与章节切片缓存一并失效，避免继续命中错位内容。
    final cacheVersion = detail.item.updatedAt?.toIso8601String() ?? '';
    if (cachedMeta != null &&
        (cachedMeta['cacheVersion']?.toString() ?? '') != cacheVersion) {
      if (kDebugMode) {
        readerDebugLog(
          'parsedBookProvider: cache version mismatch for $itemId, purging',
        );
      }
      await localStorage.deleteBookMeta(itemId);
      await localStorage.deleteChaptersForItem(itemId);
      cachedMeta = null;
    }
    if (cachedMeta != null && (itemType == 'EPUB' || itemType == 'TXT')) {
      if (kDebugMode) {
        readerDebugLog('parsedBookProvider: SQLite cache hit for $itemId');
      }
      final book = _deserializeBookMeta(cachedMeta);
      if (book != null && canReuseParsedBookMetadata(itemType, book)) {
        memoryCache.write(itemId, book);
        return book;
      }
      await localStorage.deleteBookMeta(itemId);
    } else if (cachedMeta != null) {
      await localStorage.deleteBookMeta(itemId);
    }

    // ── Layer 3: 服务端持久化清单 ──
    if (kDebugMode) {
      readerDebugLog(
        'parsedBookProvider: cache miss, loading from network for $itemId',
      );
    }

    final api = ref.read(readerApiProvider);
    if (kDebugMode) {
      readerDebugLog(
        'parsedBookProvider: itemType=$itemType, title=${detail.item.title}',
      );
    }

    final book = await _awaitServerTextManifest(api, itemId);

    // 写入 SQLite 持久化缓存
    await _saveBookMetaToSqlite(
      localStorage,
      itemId,
      book,
      itemType: itemType,
      cacheVersion: cacheVersion,
    );

    // 写入内存 LRU
    memoryCache.write(itemId, book);
    return book;
  } finally {
    keepAliveLink.close();
  }
});

/// 导入完成后立即在后台准备文本书籍，解析过程不会因离开导入页面而中断。
void startBackgroundBookPreparation(WidgetRef ref, ReaderItem item) {
  if (item.isComic) {
    return;
  }
  unawaited(
    ref.read(parsedBookProvider(item.id).future).onError((error, stackTrace) {
      if (kDebugMode) {
        readerDebugLog('后台书籍解析失败: itemId=${item.id}, error=$error');
      }
      return const ParsedBook(chapters: []);
    }),
  );
}

/// 按需加载单个章节的 XHTML 内容
///
/// 原生平台从会话明文文件按需读取，Web 使用有界内存字节。
Future<String?> loadChapterContent(
  WidgetRef ref,
  String itemId,
  ParsedChapter chapter,
) async {
  if (chapter.xhtmlContent.isNotEmpty) return chapter.xhtmlContent;
  final detail = await ref.read(readerItemDetailProvider(itemId).future);
  if (detail.item.itemType == 'TXT') {
    final start = chapter.sourceStartOffset;
    final end = chapter.sourceEndOffset;
    if (start == null || end == null || end < start) return null;
    final source = await ref.read(cachedBookHandleProvider(itemId).future);
    final parser = ref.read(txtParserServiceProvider);
    // Web 受整包内存上限约束；原生放宽到会话级解码上限，超限给出
    // 明确错误而非静默失败。整本解码按条目缓存，切章不再重复解码。
    final bytes = await source.readBytes(
      maxBytes:
          source.isMemory
              ? LocalBookCache.maxInMemoryParseBytes
              : LocalBookCache.maxNativeParseBytes,
    );
    final text = await parser.ensureDecodedText(itemId: itemId, bytes: bytes);
    return parser.chapterFromText(text, start, end);
  }
  if (detail.item.itemType != 'EPUB') return chapter.xhtmlContent;

  final contentPath = chapter.contentPath;
  if (contentPath == null) return null;

  final source = await ref.read(cachedBookHandleProvider(itemId).future);
  final epubService = ref.read(epubParserServiceProvider(itemId));
  final bytes = source.memoryBytes;
  if (bytes != null) {
    if (bytes.isEmpty) return null;
    return epubService.parseChapter(bytes, contentPath);
  }
  final path = await source.openFilePath();
  return path == null ? null : epubService.parseChapterFile(path, contentPath);
}

/// 判断持久化的书籍元数据是否足以重新按需加载章节正文。
bool canReuseParsedBookMetadata(String itemType, ParsedBook book) {
  if (book.chapters.isEmpty) return false;
  if (itemType == 'EPUB') {
    return book.chapters.every(
      (chapter) => chapter.contentPath?.trim().isNotEmpty == true,
    );
  }
  if (itemType == 'TXT') {
    return book.chapters.every(
      (chapter) =>
          chapter.sourceStartOffset != null && chapter.sourceEndOffset != null,
    );
  }
  return false;
}

Future<ParsedBook> _awaitServerTextManifest(
  ReaderApi api,
  String itemId,
) async {
  const maxAttempts = 40;
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final manifest = await api.getTextManifest(itemId);
    if (manifest.importStatus == ReaderImportStatus.ready &&
        manifest.book.chapters.isNotEmpty) {
      return manifest.book;
    }
    if (manifest.importStatus == ReaderImportStatus.failed) {
      throw AppException(
        code: manifest.errorCode ?? 'READER_PARSE_FAILED',
        message: manifest.errorMessage ?? '书籍解析失败',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw const AppException(
    code: 'READER_PARSE_PENDING',
    message: '书籍仍在后台解析，请稍后重试',
  );
}

/// 将路由、目录或历史进度中的章节标识解析为书籍章节索引。
///
/// 未知章节标识返回 null（显式失败），由调用方决定忽略请求或提示错误；
/// 禁止静默回退到第一章伪造目标位置。
int? resolveParsedChapterIndex(ParsedBook book, String chapterId) {
  if (book.chapters.isEmpty) return null;

  final indexMatch = RegExp(r'^chapter_(\d+)$').firstMatch(chapterId);
  if (indexMatch != null) {
    final index = int.parse(indexMatch.group(1)!);
    if (index >= 0 && index < book.chapters.length) return index;
  }

  final contentPath = chapterId.split('#').first;
  final pathIndex = book.chapters.indexWhere(
    (chapter) => chapter.contentPath == contentPath,
  );
  if (pathIndex >= 0) return pathIndex;

  final titleIndex = book.chapters.indexWhere(
    (chapter) => chapter.title == chapterId,
  );
  return titleIndex >= 0 ? titleIndex : null;
}

/// 返回客户端阅读器使用的规范章节标识。
String canonicalReaderChapterId(ParsedBook book, String chapterId) {
  final index = resolveParsedChapterIndex(book, chapterId);
  return index == null ? chapterId : 'chapter_$index';
}

/// 将 TXT 等内联章节正文转换为阅读器内容。
ReaderChapterContent? inlineReaderChapterContent(ParsedChapter chapter) {
  final content = chapter.xhtmlContent.trim();
  if (content.isEmpty) return null;
  return ReaderChapterContent(
    title: chapter.title,
    content: content,
    wordCount: chapter.charCount > 0 ? chapter.charCount : content.length,
  );
}

/// 返回章节正文的本地缓存键。
///
/// EPUB 使用归档路径，TXT 使用服务端持久化的字符偏移区间。
String? readerChapterCacheKey(ParsedChapter chapter) {
  final contentPath = chapter.contentPath?.trim();
  if (contentPath != null && contentPath.isNotEmpty) {
    return contentPath;
  }
  final start = chapter.sourceStartOffset;
  final end = chapter.sourceEndOffset;
  if (start == null || end == null || start < 0 || end < start) {
    return null;
  }
  return 'txt/$start-$end.xhtml';
}

/// 进程内章节正文 LRU：避免每次 build/预取都打 SQLite。
/// key = itemId|cacheKey，value = 预处理后的 ReaderChapterContent。
final _chapterContentMemoryCache = <String, ReaderChapterContent>{};
const _chapterContentMemoryCacheLimit = 12;

/// 在途加载去重：同一章并发请求共用一次 Future，避免重复解压/预处理。
final _chapterContentInflight = <String, Future<ReaderChapterContent?>>{};

void _rememberChapterContent(String key, ReaderChapterContent content) {
  _chapterContentMemoryCache.remove(key);
  _chapterContentMemoryCache[key] = content;
  while (_chapterContentMemoryCache.length > _chapterContentMemoryCacheLimit) {
    _chapterContentMemoryCache.remove(_chapterContentMemoryCache.keys.first);
  }
}

/// 获取指定章节内容（内存 LRU + 在途去重 + SQLite 缓存 + 预处理）
Future<ReaderChapterContent?> getChapterContent(
  WidgetRef ref,
  String itemId,
  ParsedBook book,
  String chapterId,
) async {
  if (book.chapters.isEmpty) return null;

  // 查找匹配的章节
  final matchedIndex = resolveParsedChapterIndex(book, chapterId);
  if (matchedIndex == null) return null;
  final matched = book.chapters[matchedIndex];

  final inlineContent = inlineReaderChapterContent(matched);
  if (inlineContent != null) return inlineContent;

  final cacheKey = readerChapterCacheKey(matched);
  if (cacheKey == null) return null;
  final memoryKey = '$itemId|$cacheKey';
  final memoryHit = _chapterContentMemoryCache[memoryKey];
  if (memoryHit != null) {
    return memoryHit;
  }
  final inflight = _chapterContentInflight[memoryKey];
  if (inflight != null) {
    return inflight;
  }
  final future = _loadChapterContentFromStorage(
    ref,
    itemId: itemId,
    matched: matched,
    cacheKey: cacheKey,
    memoryKey: memoryKey,
  );
  _chapterContentInflight[memoryKey] = future;
  try {
    return await future;
  } finally {
    _chapterContentInflight.remove(memoryKey);
  }
}

Future<ReaderChapterContent?> _loadChapterContentFromStorage(
  WidgetRef ref, {
  required String itemId,
  required ParsedChapter matched,
  required String cacheKey,
  required String memoryKey,
}) async {
  // ── Layer 1: SQLite 章节缓存命中 ──
  final localStorage = ref.read(readerLocalStorageProvider);
  final cachedHtml = await localStorage.loadChapterContent(
    itemId: itemId,
    contentPath: cacheKey,
  );
  if (cachedHtml != null && cachedHtml.isNotEmpty) {
    // 注意：cachedHtml 是预处理后的 HTML（含占位符/标签），
    // matched.charCount 是解析出的纯文本字数，两者单位不同。
    // 不能用 charCount 严格校验 HTML 长度，否则会把正常章节
    // （剥离脚本/样式/空白后变短）误判为损坏并反复清空。
    // 仅在内容为空或相对解析规模极端短时视为损坏。
    final expectedChars = matched.charCount;
    final isCorrupted =
        cachedHtml.trim().isEmpty ||
        (expectedChars > 2000 && cachedHtml.length < 200);
    if (isCorrupted) {
      if (kDebugMode) {
        readerDebugLog(
          'BookProvider: cache invalid — "${matched.title}" '
          'cached=${cachedHtml.length} chars, expected=$expectedChars. Purging chapter.',
        );
      }
      await localStorage.deleteChapter(itemId, cacheKey);
    } else {
      if (kDebugMode) {
        readerDebugLog(
          'BookProvider: SQLite chapter cache hit — '
          '"${matched.title}" (${cachedHtml.length} chars)',
        );
      }
      // 不再转为 data URI — 保持 __IMG_xxx__ 占位符，渲染时直接从 SQLite 加载
      final content = ReaderChapterContent(
        title: matched.title,
        content: cachedHtml,
        wordCount: expectedChars > 0 ? expectedChars : cachedHtml.length,
      );
      _rememberChapterContent(memoryKey, content);
      return content;
    }
  }

  // ── Layer 2: 从 EPUB 提取 + 预处理（图片存磁盘，HTML 用占位符） ──
  if (kDebugMode) {
    readerDebugLog(
      'BookProvider: loading chapter — '
      '"${matched.title}", contentPath=$cacheKey',
    );
  }

  final xhtml = await loadChapterContent(ref, itemId, matched);
  if (xhtml == null) return null;

  final contentPath = matched.contentPath?.trim();
  if (contentPath == null || contentPath.isEmpty) {
    final storageHtml = await ReaderContentPreprocessor.preprocessForStorage(
      itemId: itemId,
      xhtml: xhtml,
    );
    await localStorage.saveChapterContent(
      itemId: itemId,
      contentPath: cacheKey,
      title: matched.title,
      chapterNumber: matched.number,
      charCount: matched.charCount,
      processedHtml: storageHtml,
    );
    final content = ReaderChapterContent(
      title: matched.title,
      content: storageHtml,
      wordCount: matched.charCount > 0 ? matched.charCount : storageHtml.length,
    );
    _rememberChapterContent(memoryKey, content);
    return content;
  }

  // 优先使用 EpubParserService 已解压的 Archive（避免重复解压）
  final epubService = ref.read(epubParserServiceProvider(itemId));
  final sharedArchive = epubService.cachedArchive;
  final source = await ref.read(cachedBookHandleProvider(itemId).future);

  // Phase 1：提取 body + 图片存磁盘 + HTML 用占位符
  final storageHtml = await ReaderContentPreprocessor.preprocessForStorage(
    itemId: itemId,
    xhtml: xhtml,
    archive: sharedArchive,
    archiveBytes: sharedArchive == null ? source.memoryBytes : null,
    contentPath: contentPath,
  );

  // 章节处理完成后释放 Archive 缓存，回收内存
  epubService.releaseArchive();

  // 写入 SQLite 缓存（HTML 含占位符，体积小）
  if (kDebugMode) {
    readerDebugLog(
      'BookProvider: saving chapter cache — '
      '"${matched.title}" ${storageHtml.length} chars, '
      'contentPath=$contentPath',
    );
  }
  await localStorage.saveChapterContent(
    itemId: itemId,
    contentPath: cacheKey,
    title: matched.title,
    chapterNumber: matched.number,
    charCount: matched.charCount,
    processedHtml: storageHtml,
  );

  if (kDebugMode) {
    readerDebugLog('BookProvider: ready — storage=${storageHtml.length} chars');
  }

  final ready = ReaderChapterContent(
    title: matched.title,
    content: storageHtml,
    wordCount: matched.charCount > 0 ? matched.charCount : storageHtml.length,
  );
  _rememberChapterContent(memoryKey, ready);
  return ready;
}

/// 清除指定书籍的解析缓存（内存 + SQLite + 图片磁盘缓存）
Future<void> invalidateBookCache(WidgetRef ref, String itemId) async {
  final parsedBookCache = ref.read(readerParsedBookCacheProvider);
  final localStorage = ref.read(readerLocalStorageProvider);
  final localBookCache = ref.read(localBookCacheProvider);
  final parserService = ref.read(epubParserServiceProvider(itemId));

  _chapterContentMemoryCache.removeWhere(
    (key, _) => key.startsWith('$itemId|'),
  );
  parsedBookCache.remove(itemId);
  parserService.releaseArchive();
  ref.invalidate(cachedBookHandleProvider(itemId));
  ref.invalidate(parsedBookProvider(itemId));
  await localStorage.deleteBookMeta(itemId);
  await localStorage.deleteChaptersForItem(itemId);
  await localBookCache.removeCache(itemId);
  await ReaderImageCache.deleteForItem(itemId);
}

// ── SQLite 辅助方法 ──

/// 将 ParsedBook 元数据写入 SQLite（不含 archiveBytes）
Future<void> _saveBookMetaToSqlite(
  ReaderLocalStorage localStorage,
  String itemId,
  ParsedBook book, {
  String itemType = 'EPUB',
  String cacheVersion = '',
}) async {
  try {
    final chaptersJson = jsonEncode(
      book.chapters
          .map(
            (c) => {
              'number': c.number,
              'title': c.title,
              'charCount': c.charCount,
              'contentPath': c.contentPath,
              'level': c.level,
              'sourceStartOffset': c.sourceStartOffset,
              'sourceEndOffset': c.sourceEndOffset,
            },
          )
          .toList(),
    );
    await localStorage.saveBookMeta(
      itemId: itemId,
      title: book.title,
      author: book.author,
      description: book.description,
      publisher: book.publisher,
      language: book.language,
      chaptersJson: chaptersJson,
      totalChars: book.chapters.fold<int>(0, (s, c) => s + c.charCount),
      itemType: itemType,
      cacheVersion: cacheVersion,
    );
    if (kDebugMode) {
      readerDebugLog('BookProvider: saved book meta to SQLite for $itemId');
    }
  } on Exception catch (e) {
    if (kDebugMode) {
      readerDebugLog('BookProvider: save book meta failed: $e');
    }
  }
}

/// 从 SQLite 反序列化 ParsedBook（不含 archiveBytes）
ParsedBook? _deserializeBookMeta(Map<String, dynamic> meta) {
  try {
    final chaptersJson = meta['chaptersJson'] as String? ?? '[]';
    final chaptersList = jsonDecode(chaptersJson) as List<dynamic>;
    final chapters =
        chaptersList
            .map(
              (c) => ParsedChapter(
                number: (c as Map<String, dynamic>)['number'] as int? ?? 0,
                title: c['title'] as String? ?? '',
                xhtmlContent: '',
                charCount: c['charCount'] as int? ?? 0,
                contentPath: c['contentPath'] as String?,
                level: c['level'] as int? ?? 0,
                sourceStartOffset: c['sourceStartOffset'] as int?,
                sourceEndOffset: c['sourceEndOffset'] as int?,
              ),
            )
            .toList();
    return ParsedBook(
      chapters: chapters,
      title: meta['title'] as String?,
      author: meta['author'] as String?,
      description: meta['description'] as String?,
      publisher: meta['publisher'] as String?,
      language: meta['language'] as String?,
    );
  } on Exception catch (e) {
    if (kDebugMode) {
      readerDebugLog('BookProvider: deserialize book meta failed: $e');
    }
    return null;
  }
}
