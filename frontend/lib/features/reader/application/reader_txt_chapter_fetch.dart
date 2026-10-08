part of 'reader_book_provider.dart';

/// 按需加载单个章节的 XHTML 内容。
///
/// TXT 优先取服务端解析时派生的单章 UTF-8 正文；派生缺失、请求失败或返回长度与
/// 本地清单不符时回退本地整本解码链。EPUB 由客户端解压，原生平台从会话明文文件
/// 按需读取，Web 使用有界内存字节。
Future<String?> loadChapterContent(
  WidgetRef ref,
  String itemId,
  ParsedChapter chapter, {
  required int chapterIndex,
}) async {
  // 章节索引必须由调用方按 parsedBook 顺序给出：传错就会拿到别章正文，
  // 而长度校验用的是同一份清单，无法自证。
  assert(
    chapterIndex == chapter.number - 1,
    'chapterIndex=$chapterIndex 与 chapter.number=${chapter.number} 不一致',
  );
  if (chapter.xhtmlContent.isNotEmpty) return chapter.xhtmlContent;
  final detail = await ref.read(readerItemDetailProvider(itemId).future);
  if (detail.item.itemType == 'TXT') {
    final start = chapter.sourceStartOffset;
    final end = chapter.sourceEndOffset;
    if (start == null || end == null || end < start) return null;
    final parser = ref.read(txtParserServiceProvider);
    final serverText = await _readTxtChapterFromServer(
      ref,
      itemId,
      chapterIndex,
      chapter,
    );
    if (serverText != null) {
      // 整章只有标题行时服务端正文为空：用章名补一段，避免出现空白页
      return parser.textToXhtml(
        serverText.isEmpty ? chapter.title : serverText,
      );
    }
    // 服务端取不到正文时的本地兜底：整本下载＋本地解码，只在离线或旧数据未重解析时走到。
    final Uint8List bytes;
    try {
      final source = await ref.read(cachedBookHandleProvider(itemId).future);
      // Web 受整包内存上限约束；原生放宽到会话级解码上限，超限给出
      // 明确错误而非静默失败。整本解码缓存由阅读页保活（见 buildReaderView）。
      bytes = await source.readBytes(
        maxBytes:
            source.isMemory
                ? LocalBookCache.maxInMemoryParseBytes
                : LocalBookCache.maxNativeParseBytes,
      );
    } on FormatException catch (error) {
      // 超过整本解析上限与联网无关，标成"需要联网"会把用户引向错误动作
      throw TxtChapterTextException('本地整本超过解析上限（chapter=$chapterIndex）：$error');
    } on Exception catch (error) {
      throw TxtChapterTextException(
        '本地整本文件不可用（chapter=$chapterIndex）：$error',
        reason: ReaderChapterFailure.needsNetwork,
      );
    }
    final text = await parser.ensureDecodedText(itemId: itemId, bytes: bytes);
    final rawSlice = parser.rawChapterSlice(text, start, end);
    // 前后端各自解码同一份字节流，编码判定或坏序列策略一有分歧，服务端偏移就会
    // 整体错位，切出来的其实是别章正文。此时宁可显式失败，也不静默渲染错章内容。
    if (!TxtParserService.sliceStartsWithTitle(rawSlice, chapter.title)) {
      readerDebugLog(
        'TxtOffsetDrift: itemId=$itemId chapterNumber=${chapter.number} '
        'offsets=$start-$end sliceChars=${rawSlice.length} '
        'titleChars=${chapter.title.length}',
      );
      throw TxtChapterTextException(
        '章节偏移与正文不匹配（chapter=$chapterIndex, span=$start-$end）',
        reason: ReaderChapterFailure.needsReparse,
      );
    }
    final body = txtChapterBody(rawSlice, chapter.bodyStartOffset);
    // 整章只有标题行时剥完标题会剩空串：保留完整切片，与服务端返回保持一致
    return parser.textToXhtml(body.isEmpty ? rawSlice : body);
  }
  if (detail.item.itemType != 'EPUB') return chapter.xhtmlContent;

  final contentPath = chapter.contentPath;
  if (contentPath == null) return null;

  final source = await ref.read(cachedBookHandleProvider(itemId).future);
  final epubService = ref.read(epubParserServiceProvider(itemId));

  // 编码不支持是可诊断的读者动作（重导或转 UTF-8），必须翻成带原因的章节失败；
  // 其它异常仍按原样上抛，交给通用加载失败文案。
  Future<String?> readWithEncodingFailure(
    Future<String?> Function() read,
  ) async {
    try {
      return await read();
    } on EpubUnsupportedEncodingException catch (error) {
      throw TxtChapterTextException(
        'EPUB 条目声明了无法解码的字符集（$error, chapter=$chapterIndex）',
        reason: ReaderChapterFailure.unsupportedEncoding,
      );
    }
  }

  final bytes = source.memoryBytes;
  if (bytes != null) {
    if (bytes.isEmpty) return null;
    return readWithEncodingFailure(
      () => epubService.parseChapter(bytes, contentPath),
    );
  }
  final path = await source.openFilePath();
  if (path == null) return null;
  return readWithEncodingFailure(
    () => epubService.parseChapterFile(path, contentPath),
  );
}

/// 读取服务端已解码的 TXT 单章正文；不可用或疑似陈旧时返回 null，交由本地链兜底。
Future<String?> _readTxtChapterFromServer(
  WidgetRef ref,
  String itemId,
  int chapterIndex,
  ParsedChapter chapter,
) async {
  final spanChars =
      (chapter.sourceEndOffset ?? 0) - (chapter.sourceStartOffset ?? 0);
  try {
    final result = await ref
        .read(readerApiProvider)
        .getChapterText(itemId, chapterIndex);
    // 起点不一致说明服务端清单与本地清单不是同一版本；正文为空但起点相同是合法状态
    if (result.bodyStartOffset != chapter.bodyStartOffset) {
      readerDebugLog(
        'TxtServerText SKIP: itemId=$itemId chapterIndex=$chapterIndex '
        'serverBodyStart=${result.bodyStartOffset} manifestBodyStart=${chapter.bodyStartOffset}',
      );
      return null;
    }
    final expectedChars = txtChapterBodyChars(
      spanChars,
      result.bodyStartOffset,
    );
    if (!txtChapterTextMatchesManifestRange(
      result.text,
      result.charCount,
      expectedChars,
    )) {
      readerDebugLog(
        'TxtServerText SKIP: itemId=$itemId chapterIndex=$chapterIndex '
        'chars=${result.charCount} expected=$expectedChars',
      );
      return null;
    }
    return result.text;
  } on Exception catch (error) {
    readerDebugLog(
      'TxtServerText FALLBACK: itemId=$itemId chapterIndex=$chapterIndex error=$error',
    );
    return null;
  }
}

/// 章节正文长度：整章区间去掉标题行及其终止符。
///
/// 起点为 0（本章首行不是标题行）时整段都是正文；起点到达区间末尾时正文为空
/// （整章只有标题行），与服务端 `substring(bodyStart)` 的口径一致。
int txtChapterBodyChars(int spanChars, int bodyStartOffset) {
  if (bodyStartOffset <= 0) return spanChars;
  return (spanChars - bodyStartOffset).clamp(0, spanChars);
}

/// 判断服务端返回的 TXT 单章正文与期望长度是否一致。
///
/// 长度必须等于清单区间去掉标题行后的长度；不一致说明返回内容与本地清单不同源，
/// 交由本地链兜底而不是直接渲染。正文为空是合法状态（整章只有标题行）。
bool txtChapterTextMatchesManifestRange(
  String text,
  int charCount,
  int expectedChars,
) {
  return charCount == expectedChars && text.length == charCount;
}

/// 从整章切片（含标题行）取出正文，起点由清单的 bodyStartOffset 给出（D-12）。
String txtChapterBody(String rawSlice, int bodyStartOffset) {
  if (bodyStartOffset <= 0) return rawSlice;
  return rawSlice.substring(bodyStartOffset.clamp(0, rawSlice.length));
}
