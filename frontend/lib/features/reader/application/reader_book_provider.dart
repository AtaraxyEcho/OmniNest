import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/features/reader/application/reader_cache_providers.dart';
import 'package:omninest/features/reader/application/reader_chapter_load_coordinator.dart';
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
import 'package:omninest/features/reader/domain/chapter_title_normalizer.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/domain/reader_status_constants.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

part 'reader_txt_chapter_fetch.dart';

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

/// PDF 阅读页持有的源文件句柄。
///
/// 与通用句柄的差别只在 Web 侧的体积档位：PDF 上限 128MiB 且失败要报专用错误码。
/// 由本页保持订阅，autoDispose 才会在页面仍映射会话文件时把它删掉。
final pdfBookHandleProvider = FutureProvider.autoDispose
    .family<CachedBookHandle, String>((ref, itemId) async {
      final api = ref.watch(readerApiProvider);
      final cache = ref.watch(localBookCacheProvider);
      final handle = await cache.ensureCachedHandle(
        itemId,
        webDownloader: () => api.downloadFileBytes(itemId, itemType: 'PDF'),
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
  // 排队中的条目同样未完成：只看 parsing 会让轮询在第一帧就退出。
  final finished =
      manifest.importStatus != ReaderImportStatus.pending &&
      manifest.importStatus != ReaderImportStatus.parsing;
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

/// TXT 解析服务实例。
///
/// 只在服务端派生正文不可用时用到，其整本解码缓存会长期占住一本书的文本，
/// 因此改为 autoDispose：随阅读页所在的 autoDispose 作用域释放（D-39）。
final txtParserServiceProvider = Provider.autoDispose<TxtParserService>((ref) {
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
    // 章节偏移与目录只在服务端重解析时变化，manifestVersion 是这件事的唯一信号；
    // 版本不符则元数据与章节切片缓存一并失效，避免继续命中错位内容。
    // 用 updatedAt 会让改标题/封面等元数据操作误清整本书的章节缓存。
    final cacheVersion = 'v${detail.item.manifestVersion}';
    if (cachedMeta != null &&
        (cachedMeta['cacheVersion']?.toString() ?? '') != cacheVersion) {
      if (kDebugMode) {
        readerDebugLog(
          'parsedBookProvider: cache version mismatch for $itemId, purging',
        );
      }
      await localStorage.deleteBookMeta(itemId);
      await localStorage.deleteChaptersForItem(itemId);
      // 进程内 LRU 与 SQLite 同源，不清会让本会话继续读到旧版本的章节正文
      _chapterContentMemoryCache.removeWhere(
        (key, _) => key.startsWith('$itemId|'),
      );
      _stylesheetPoolMemo.remove(itemId);
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
/// 先按清单身份键匹配，再按 EPUB 归档路径匹配（带 `#` 锚的旧式标识取路径段）。
/// 不按标题匹配：标题是会被解析规则改写的显示文本，同名的卷/章也不止一处。
/// 未知章节标识返回 null（显式失败），由调用方决定忽略请求或提示错误；
/// 禁止静默回退到第一章伪造目标位置。
int? resolveParsedChapterIndex(ParsedBook book, String chapterId) {
  if (book.chapters.isEmpty) return null;

  final keyIndex = book.chapters.indexWhere(
    (chapter) => parsedChapterId(chapter) == chapterId,
  );
  if (keyIndex >= 0) return keyIndex;

  final contentPath = chapterId.split('#').first;
  final pathIndex = book.chapters.indexWhere(
    (chapter) => chapter.contentPath == contentPath,
  );
  return pathIndex >= 0 ? pathIndex : null;
}

/// 返回客户端阅读器使用的规范章节标识。
///
/// 规范化到清单身份键：路由或本地进度里的旧式片段（带 `#` 锚、EPUB 归档路径）
/// 先解析回所属章节，再统一换成该章的键，避免同一章的两种写法各自落库。
String canonicalReaderChapterId(ParsedBook book, String chapterId) {
  final index = resolveParsedChapterIndex(book, chapterId);
  return index == null ? chapterId : parsedChapterId(book.chapters[index]);
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
  // 正文起点参与键值：同一区间在剥掉标题行前后是不同的正文内容
  return 'txt/$start-$end@${chapter.bodyStartOffset}.xhtml';
}

/// 进程内章节正文 LRU：避免每次 build/预取都打 SQLite。
/// key = itemId|cacheKey，value = 预处理后的 ReaderChapterContent。
final _chapterContentMemoryCache = <String, ReaderChapterContent>{};
const _chapterContentMemoryCacheLimit = 12;

/// 在途加载去重：同一章并发请求共用一次 Future，避免重复解压/预处理。
final _chapterContentInflight = <String, Future<ReaderChapterContent?>>{};

/// 换号/登出时清空进程内章节与样式表缓存；这些键不含用户 ID。
void clearReaderBookMemoryCaches() {
  _readerBookMemoryGeneration++;
  _chapterContentMemoryCache.clear();
  _chapterContentInflight.clear();
  _stylesheetPoolMemo.clear();
}

int _readerBookMemoryGeneration = 0;

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
  final generation = _readerBookMemoryGeneration;
  final future = _loadChapterContentFromStorage(
    ref,
    itemId: itemId,
    matched: matched,
    chapterIndex: matchedIndex,
    cacheKey: cacheKey,
    memoryKey: memoryKey,
    generation: generation,
  );
  _chapterContentInflight[memoryKey] = future;
  try {
    final content = await future;
    return generation == _readerBookMemoryGeneration ? content : null;
  } finally {
    _chapterContentInflight.remove(memoryKey);
  }
}

Future<ReaderChapterContent?> _loadChapterContentFromStorage(
  WidgetRef ref, {
  required String itemId,
  required ParsedChapter matched,
  required int chapterIndex,
  required String cacheKey,
  required String memoryKey,
  required int generation,
}) async {
  // ── Layer 1: SQLite 章节缓存命中 ──
  final localStorage = ref.read(readerLocalStorageProvider);
  final cached = await localStorage.loadChapterContent(
    itemId: itemId,
    contentPath: cacheKey,
  );
  final cachedHtml = cached?.html;
  if (cached != null && cachedHtml != null && cachedHtml.isNotEmpty) {
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
        stylesheetCss: await _chapterStylesheetCss(
          localStorage,
          itemId,
          cached.refs,
        ),
      );
      if (generation != _readerBookMemoryGeneration) {
        return null;
      }
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

  // 归档-backed 章节（EPUB）必须在一次租约内完成"解析＋图片预处理"：预处理逐张
  // 图片 await 落盘，期间归档不能被邻章预取关掉文件流或换路径（D-29）。
  // 释放放在 finally：提前返回或预处理抛异常都会漏掉释放，Windows 上连带
  // 会话明文文件删不掉（D-30）。
  final contentPath = matched.contentPath?.trim() ?? '';
  final useArchive = contentPath.isNotEmpty;
  final epubService =
      useArchive ? ref.read(epubParserServiceProvider(itemId)) : null;
  final lease = epubService == null ? null : await epubService.acquireLease();
  try {
    final chapter = await loadChapterContent(
      ref,
      itemId,
      matched,
      chapterIndex: chapterIndex,
    );
    if (chapter == null) return null;
    final xhtml = chapter.xhtml;

    final String storageHtml;
    final int droppedImageCount;
    if (!useArchive) {
      final preprocessed = await ReaderContentPreprocessor.preprocessForStorage(
        itemId: itemId,
        xhtml: xhtml,
      );
      storageHtml = preprocessed.html;
      droppedImageCount = preprocessed.droppedImageCount;
    } else {
      // 优先使用 EpubParserService 已解压的 Archive（避免重复解压）；
      // Web 没有共享归档时退回整包字节解析。
      final sharedArchive = epubService!.cachedArchive;
      final source = await ref.read(cachedBookHandleProvider(itemId).future);
      final preprocessed = await ReaderContentPreprocessor.preprocessForStorage(
        itemId: itemId,
        xhtml: xhtml,
        archive: sharedArchive,
        archiveBytes: sharedArchive == null ? source.memoryBytes : null,
        contentPath: contentPath,
        // 归档字节必须经解析服务读取，图片才会计入它的解压与保留量闸门。
        readEntryBytes:
            sharedArchive == null ? null : epubService.readArchiveEntryBytes,
      );
      storageHtml = preprocessed.html;
      droppedImageCount = preprocessed.droppedImageCount;
    }

    // 样式表池落库只有这一条通路：元数据是在"没有归档可开"的服务端清单路径上
    // 写下的（见 parsedBookProvider 的 Layer 3），拿得到 CSS 的只有持租约的本章。
    // 本章的次序引用随章节行落库，正文里不再有那份 `<style>` 载体。
    final pool = await _ensureStylesheetPool(
      localStorage,
      itemId,
      chapter.stylesheetPool,
    );
    final stylesheetCss = buildChapterStylesheetCss(
      pool,
      chapter.stylesheetRefs,
    );

    // SQLite 只存"体积小"的占位符 HTML。图片提取失败时正文可能仍带着
    // base64 内嵌图（单章可达数 MB），落库会长期占住缓存且不自愈；
    // 这种情况只保留本次会话的内存结果，下次打开重新提取。
    final expectedStoredChars = expectedStoredChapterChars(
      contentChars: matched.charCount,
    );
    final tooLargeToStore = storageHtml.length > expectedStoredChars;
    if (tooLargeToStore) {
      if (kDebugMode) {
        readerDebugLog(
          'BookProvider: 章节正文体积异常，跳过持久化 — '
          '"${matched.title}" chars=${matched.charCount} '
          'html=${storageHtml.length} limit=$expectedStoredChars',
        );
      }
    } else {
      if (kDebugMode) {
        readerDebugLog(
          'BookProvider: saving chapter cache — '
          '"${matched.title}" ${storageHtml.length} chars, '
          'contentPath=$cacheKey',
        );
      }
      await localStorage.saveChapterContent(
        itemId: itemId,
        contentPath: cacheKey,
        title: matched.title,
        chapterNumber: matched.number,
        charCount: matched.charCount,
        processedHtml: storageHtml,
        stylesheetRefs: chapter.stylesheetRefs,
      );
    }

    if (kDebugMode) {
      readerDebugLog(
        'BookProvider: ready — storage=${storageHtml.length} chars',
      );
    }

    final ready = ReaderChapterContent(
      title: matched.title,
      content: storageHtml,
      wordCount: matched.charCount > 0 ? matched.charCount : storageHtml.length,
      droppedImageCount: droppedImageCount,
      stylesheetCss: stylesheetCss,
    );
    if (generation != _readerBookMemoryGeneration) {
      return null;
    }
    _rememberChapterContent(memoryKey, ready);
    return ready;
  } finally {
    lease?.release();
  }
}

/// 清除指定书籍的解析缓存（内存 + SQLite + 图片磁盘缓存）。
///
/// 参数取 `Ref` 而不是 `WidgetRef`：作废必须跟着"重新解析"这条业务流程走，而流程
/// 归 application 层。以前它挂在页面按钮上（详情页那条入口根本没调用），两个入口
/// 各自决定要不要清，迟早有一个忘 —— 缓存留着旧结构，读者看到的还是重解析前的内容。
Future<void> invalidateBookCache(Ref ref, String itemId) async {
  final parsedBookCache = ref.read(readerParsedBookCacheProvider);
  final localStorage = ref.read(readerLocalStorageProvider);
  final localBookCache = ref.read(localBookCacheProvider);
  final parserService = ref.read(epubParserServiceProvider(itemId));

  _chapterContentMemoryCache.removeWhere(
    (key, _) => key.startsWith('$itemId|'),
  );
  _stylesheetPoolMemo.remove(itemId);
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
              'chapterKey': c.chapterKey,
              'charCount': c.charCount,
              'contentPath': c.contentPath,
              'level': c.level,
              'sourceStartOffset': c.sourceStartOffset,
              'sourceEndOffset': c.sourceEndOffset,
              'bodyStartOffset': c.bodyStartOffset,
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
                chapterKey: c['chapterKey'] as String?,
                xhtmlContent: '',
                charCount: c['charCount'] as int? ?? 0,
                contentPath: c['contentPath'] as String?,
                level: c['level'] as int? ?? 0,
                sourceStartOffset: c['sourceStartOffset'] as int?,
                sourceEndOffset: c['sourceEndOffset'] as int?,
                bodyStartOffset: c['bodyStartOffset'] as int? ?? 0,
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

/// 一章正文允许落库的字符上限。
///
/// 正文异常的真实来源是图片提取失败后残留的 base64 内嵌图，单章可达数 MB；
/// 样式表已经不进正文（书级池 + 章节次序引用），所以这里不再有样式表的放行额度。
int expectedStoredChapterChars({required int contentChars}) {
  return contentChars * 6 + 64 * 1024;
}

/// 进程内样式表池：itemId → (归档内路径 → CSS 文本)。
///
/// 一本书一份，避免每章读取都打一次 SQLite 并把整池解密一遍。作废与章节正文
/// 缓存在同一处发生（清单版本不符、重新解析）。整池可以上百 KB，所以与章节 LRU
/// 一样要有上限：一次会话里翻过很多本书时不能把它们全留在内存里。
final _stylesheetPoolMemo = <String, Map<String, String>>{};
const _stylesheetPoolMemoLimit = 4;

void _rememberStylesheetPool(String itemId, Map<String, String> pool) {
  _stylesheetPoolMemo.remove(itemId);
  _stylesheetPoolMemo[itemId] = pool;
  while (_stylesheetPoolMemo.length > _stylesheetPoolMemoLimit) {
    _stylesheetPoolMemo.remove(_stylesheetPoolMemo.keys.first);
  }
}

/// 取这本书的样式表池；库里没有而本章带回了样式表时，就地补写一次。
///
/// 返回本章该用的池：写成功就是刚拿到的那份，写不成（元数据行还没落地）也用
/// 它渲染本章，只是不记进 memo —— 下一章重试，别让一本书静默失去原版排版。
Future<Map<String, String>> _ensureStylesheetPool(
  ReaderLocalStorage localStorage,
  String itemId,
  Map<String, String> fromArchive,
) async {
  if (fromArchive.isEmpty) return const {};
  final memo = _stylesheetPoolMemo[itemId];
  if (memo != null && memo.isNotEmpty) return memo;
  final stored = await localStorage.loadStylesheetPool(itemId);
  if (stored.isNotEmpty) {
    _rememberStylesheetPool(itemId, stored);
    return stored;
  }
  final written = await localStorage.saveStylesheetPool(
    itemId: itemId,
    pool: fromArchive,
  );
  if (written) {
    _rememberStylesheetPool(itemId, fromArchive);
  } else {
    readerDebugLog('BookProvider: 样式表池未能落库（元数据行缺失）itemId=$itemId');
  }
  return fromArchive;
}

/// 按本章次序引用拼出解析侧要的样式表全文（缓存命中通路）。
Future<String> _chapterStylesheetCss(
  ReaderLocalStorage localStorage,
  String itemId,
  List<String> refs,
) async {
  if (refs.isEmpty) return '';
  final memo = _stylesheetPoolMemo[itemId];
  if (memo != null) return buildChapterStylesheetCss(memo, refs);
  final stored = await localStorage.loadStylesheetPool(itemId);
  _rememberStylesheetPool(itemId, stored);
  return buildChapterStylesheetCss(stored, refs);
}
