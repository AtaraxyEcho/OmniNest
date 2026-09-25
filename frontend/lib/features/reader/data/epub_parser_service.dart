import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:gbk_codec/gbk_codec.dart';
import 'package:omninest/core/config/file_size_thresholds.dart';
import 'package:omninest/features/reader/data/epub_archive_loader.dart';
import 'package:omninest/features/reader/data/epub_archive_source.dart';
import 'package:omninest/features/reader/domain/parsed_book.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';
import 'package:xml/xml.dart';

/// 按条目声明解码 EPUB 内部文本。
///
/// 中文圈常见旧制 EPUB 的内部 XHTML/OPF 为 GBK 编码；严格 utf8 解码会
/// 抛异常导致章节静默空白。优先读取 XML 声明的 encoding，声明为 GBK
/// 系列时用 GBK 解码，其余按宽松 utf8 处理避免坏字节毁掉整章。
String decodeEpubText(List<int> bytes) {
  final declared = _declaredEncoding(bytes);
  if (declared != null && _isGbkFamily(declared)) {
    return gbk.decode(bytes);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

String? _declaredEncoding(List<int> bytes) {
  final head = utf8.decode(bytes.take(200).toList(), allowMalformed: true);
  final match = RegExp(
    r'''encoding\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  ).firstMatch(head);
  return match?.group(1)?.trim();
}

bool _isGbkFamily(String name) {
  final normalized = name.replaceAll('-', '').toLowerCase();
  return normalized == 'gbk' ||
      normalized == 'gb2312' ||
      normalized == 'gb18030';
}

/// EPUB 归档超过安全解析边界。
class EpubParseLimitException implements Exception {
  const EpubParseLimitException(this.message);

  final String message;

  @override
  String toString() => 'EpubParseLimitException: $message';
}

/// EPUB 文件解析服务
///
/// 从 EPUB ZIP 归档中提取元数据、封面和章节内容。
/// 使用 archive + xml 包，不依赖 epubx（避免 image 版本冲突）。
class EpubParserService {
  static const _maxArchiveEntries = 10000;
  static const _maxExpandedBytes = 1024 * 1024 * 1024;
  static const _maxExpansionRatio = 250;
  static const _ratioCheckThresholdBytes = 64 * 1024 * 1024;
  static const _maxTextEntryBytes = 8 * 1024 * 1024;
  static const _maxCoverBytes = FileSizeThresholds.epubCoverMaxBytes;

  /// 缓存已解压的 Archive，避免重复解压整个 ZIP 归档。
  Archive? _cachedArchive;
  int? _cachedArchiveHash;
  int? _cachedArchiveLength;
  String? _cachedArchivePath;
  EpubArchiveSource? _fileSource;

  /// 获取缓存的 Archive，未命中时解压并缓存。
  ///
  /// 使用长度 + 内容哈希判断缓存命中，避免 Uint8List 引用比较问题。
  Archive? _getCachedArchive(Uint8List archiveBytes) {
    final hash = _computeHash(archiveBytes);
    if (_cachedArchive != null &&
        _cachedArchiveLength == archiveBytes.length &&
        _cachedArchiveHash == hash) {
      return _cachedArchive;
    }
    releaseArchive();
    final archive = ZipDecoder().decodeBytes(archiveBytes);
    _validateArchive(archive, archiveBytes.length);
    _cachedArchive = archive;
    _cachedArchiveHash = hash;
    _cachedArchiveLength = archiveBytes.length;
    return _cachedArchive;
  }

  Archive? _getCachedFileArchive(String path) {
    if (_cachedArchive != null && _cachedArchivePath == path) {
      return _cachedArchive;
    }
    releaseArchive();
    final source = openEpubArchiveFile(path);
    try {
      final compressedBytes = source.archive.files.fold<int>(
        0,
        (sum, file) => sum + (file.rawContent?.length ?? 0),
      );
      _validateArchive(source.archive, compressedBytes);
      _fileSource = source;
      _cachedArchive = source.archive;
      _cachedArchivePath = path;
      return _cachedArchive;
    } catch (_) {
      source.close();
      rethrow;
    }
  }

  /// 释放解压缓存的 Archive 对象，回收内存。
  ///
  /// 在章节加载完成后调用，避免 Archive 常驻内存。
  /// 下次需要时会自动重新解压。
  void releaseArchive() {
    _fileSource?.close();
    _fileSource = null;
    _cachedArchive = null;
    _cachedArchiveHash = null;
    _cachedArchiveLength = null;
    _cachedArchivePath = null;
  }

  /// 获取当前缓存的 Archive（供外部共享使用，避免重复解压）。
  Archive? get cachedArchive => _cachedArchive;

  /// 计算字节数组的快速哈希（采样 + 长度）。
  int _computeHash(Uint8List bytes) {
    // 采样首尾各 100 字节 + 长度，平衡速度和碰撞率
    var hash = bytes.length;
    final sampleSize = bytes.length < 200 ? bytes.length : 100;
    for (var i = 0; i < sampleSize; i++) {
      hash = hash * 31 + bytes[i];
    }
    for (var i = bytes.length - sampleSize; i < bytes.length; i++) {
      hash = hash * 31 + bytes[i];
    }
    return hash;
  }

  /// 解析 EPUB 元数据和章节目录
  Future<ParsedBook> parseMetadata(Uint8List bytes) {
    releaseArchive();
    return _parseMetadataArchive(() => _getCachedArchive(bytes));
  }

  /// 从原生文件流解析 EPUB 元数据和章节目录。
  Future<ParsedBook> parseMetadataFile(String path) {
    releaseArchive();
    return _parseMetadataArchive(() => _getCachedFileArchive(path));
  }

  Future<ParsedBook> _parseMetadataArchive(
    Archive? Function() loadArchive,
  ) async {
    try {
      final archive = loadArchive();
      if (archive == null) {
        if (kDebugMode) {
          readerDebugLog('EPUB: failed to decode archive');
        }
        return const ParsedBook(chapters: []);
      }

      // 1. 从 container.xml 找到 OPF 路径
      final containerEntry = _findEntry(archive, 'META-INF/container.xml');
      if (containerEntry == null) {
        if (kDebugMode) {
          readerDebugLog('EPUB: container.xml not found');
        }
        return const ParsedBook(chapters: []);
      }
      final opfPath = _parseContainerXml(_entryBytes(containerEntry));
      if (opfPath == null) {
        if (kDebugMode) {
          readerDebugLog('EPUB: OPF path not found in container.xml');
        }
        return const ParsedBook(chapters: []);
      }

      // 2. 读取并解析 OPF
      final opfEntry = _findEntry(archive, opfPath);
      if (opfEntry == null) {
        if (kDebugMode) {
          readerDebugLog('EPUB: OPF file not found at $opfPath');
        }
        return const ParsedBook(chapters: []);
      }
      final opfContent = decodeEpubText(_entryBytes(opfEntry));
      final opfDoc = XmlDocument.parse(opfContent);

      // 3. 提取元数据
      final title = _getDcElement(opfDoc, 'title');
      final author = _getDcElement(opfDoc, 'creator');
      final description = _getDcElement(opfDoc, 'description');
      final publisher = _getDcElement(opfDoc, 'publisher');
      final language = _getDcElement(opfDoc, 'language');

      // 4. 提取封面图片
      final coverBytes = _extractCover(opfDoc, archive, opfPath);

      // 5. 构建 manifest (id → href)
      final manifest = _buildManifest(opfDoc);

      // 6. 构建 spine（章节阅读顺序）
      final spine = _buildSpine(opfDoc, manifest);

      // 7. 解析 TOC 获取层级结构
      final tocLevels = _parseTocLevels(archive, opfDoc, opfPath);

      // 8. 提取章节元数据
      final chapters = <ParsedChapter>[];
      for (var i = 0; i < spine.length; i++) {
        final href = spine[i];
        final fullPath = _resolvePath(opfPath, href);
        final fileEntry = _findEntry(archive, fullPath);

        String? chapterTitle;
        int charCount = 0;
        if (fileEntry != null) {
          try {
            final xhtml = decodeEpubText(_entryBytes(fileEntry));
            chapterTitle = _extractTitleFromHtml(xhtml);
            charCount = _stripHtml(xhtml).length;
          } on EpubParseLimitException {
            rethrow;
          } catch (e) {
            if (kDebugMode) {
              readerDebugLog('EPUB: chapter $href parse failed: $e');
            }
          }
        }

        // 从 TOC 层级中获取当前章节的嵌套深度
        final level = _findTocLevel(tocLevels, href, opfPath);
        if (kDebugMode) {
          readerDebugLog(
            'EPUB: chapter $i "$chapterTitle" level=$level href=$href',
          );
        }

        chapters.add(
          ParsedChapter(
            number: i + 1,
            title: chapterTitle ?? '第${i + 1}章',
            xhtmlContent: '',
            charCount: charCount,
            contentPath: href,
            level: level,
          ),
        );
      }

      if (kDebugMode) {
        readerDebugLog(
          'EPUB: parsed "${title ?? 'unknown'}" by ${author ?? 'unknown'}, '
          '${chapters.length} chapters, cover=${coverBytes != null}',
        );
      }

      return ParsedBook(
        chapters: chapters,
        title: title,
        author: author,
        description: description,
        publisher: publisher,
        language: language,
        coverBytes: coverBytes,
      );
    } on EpubParseLimitException {
      rethrow;
    } catch (e, stack) {
      if (kDebugMode) {
        readerDebugLog('EPUB: parseMetadata failed: $e\n$stack');
      }
      return const ParsedBook(chapters: []);
    }
  }

  /// 判断 EPUB 是否为固定版式（漫画/图片型 EPUB）。
  ///
  /// 检查 OPF 中的 `rendition:layout` 属性。
  /// 返回 `true` 表示 pre-paginated（固定版式），应按漫画方式解析。
  bool isFixedLayout(Uint8List bytes) {
    releaseArchive();
    return _isFixedLayoutArchive(() => _getCachedArchive(bytes));
  }

  /// 从原生文件流判断 EPUB 是否为固定版式。
  bool isFixedLayoutFile(String path) {
    releaseArchive();
    return _isFixedLayoutArchive(() => _getCachedFileArchive(path));
  }

  bool _isFixedLayoutArchive(Archive? Function() loadArchive) {
    try {
      final archive = loadArchive();
      if (archive == null) return false;

      final containerEntry = _findEntry(archive, 'META-INF/container.xml');
      if (containerEntry == null) return false;

      final opfPath = _parseContainerXml(_entryBytes(containerEntry));
      if (opfPath == null) return false;

      final opfEntry = _findEntry(archive, opfPath);
      if (opfEntry == null) return false;

      final opfContent = decodeEpubText(_entryBytes(opfEntry));
      final opfXml = XmlDocument.parse(opfContent);

      // 检查 rendition:layout
      for (final meta in opfXml.findAllElements('meta')) {
        final property = meta.getAttribute('property');
        if (property == 'rendition:layout') {
          final value = meta.innerText.trim();
          if (value == 'pre-paginated') return true;
        }
      }

      return false;
    } on EpubParseLimitException {
      rethrow;
    } catch (_) {
      return false;
    }
  }

  /// 按需解析单个章节的 XHTML 内容
  Future<String?> parseChapter(Uint8List archiveBytes, String contentPath) {
    releaseArchive();
    return _parseChapterArchive(
      () => _getCachedArchive(archiveBytes),
      contentPath,
    );
  }

  /// 从原生文件流按需解析单个章节。
  Future<String?> parseChapterFile(String path, String contentPath) {
    releaseArchive();
    return _parseChapterArchive(() => _getCachedFileArchive(path), contentPath);
  }

  Future<String?> _parseChapterArchive(
    Archive? Function() loadArchive,
    String contentPath,
  ) async {
    try {
      final archive = loadArchive();
      if (archive == null) return null;

      final containerEntry = _findEntry(archive, 'META-INF/container.xml');
      if (containerEntry == null) return null;
      final opfPath = _parseContainerXml(_entryBytes(containerEntry));
      if (opfPath == null) return null;

      final directPath = _normalizeArchivePath(
        Uri.decodeComponent(contentPath),
      );
      final fullPath = _resolvePath(opfPath, contentPath);
      final fileEntry =
          _findExactEntry(archive, fullPath) ??
          _findExactEntry(archive, directPath) ??
          _findEntry(archive, fullPath);
      if (fileEntry == null) {
        if (kDebugMode) {
          readerDebugLog('EPUB: chapter file not found: $fullPath');
        }
        return null;
      }

      return decodeEpubText(_entryBytes(fileEntry));
    } on EpubParseLimitException {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        readerDebugLog('EPUB: parseChapter failed for $contentPath: $e');
      }
      return null;
    }
  }

  // ── Private helpers ──────────────────────────────────────────

  /// 在归档中查找文件（忽略大小写和前导斜杠）
  ArchiveFile? _findEntry(Archive archive, String path) {
    // 直接匹配
    var entry = archive.findFile(path);
    if (entry != null) return entry;

    // 去掉前导斜杠
    if (path.startsWith('/')) {
      entry = archive.findFile(path.substring(1));
      if (entry != null) return entry;
    }

    // 尝试小写路径
    entry = archive.findFile(path.toLowerCase());
    if (entry != null) return entry;

    // 遍历所有条目做模糊匹配
    for (final file in archive.files) {
      if (file.name.toLowerCase().endsWith(path.toLowerCase()) ||
          path.toLowerCase().endsWith(file.name.toLowerCase())) {
        return file;
      }
    }
    return null;
  }

  ArchiveFile? _findExactEntry(Archive archive, String path) {
    final normalizedPath = _normalizeArchivePath(path).toLowerCase();
    for (final file in archive.files) {
      if (_normalizeArchivePath(file.name).toLowerCase() == normalizedPath) {
        return file;
      }
    }
    return null;
  }

  /// 校验归档目录和展开容量边界。
  void _validateArchive(Archive archive, int compressedBytes) {
    if (archive.files.length > _maxArchiveEntries) {
      throw const EpubParseLimitException('EPUB 归档条目数量超过 10000');
    }
    var expandedBytes = 0;
    for (final file in archive.files) {
      if (file.isSymbolicLink) {
        throw EpubParseLimitException('EPUB 不允许符号链接条目: ${file.name}');
      }
      final normalized = file.name.replaceAll('\\', '/');
      final segments = normalized.split('/');
      if (normalized.startsWith('/') || segments.contains('..')) {
        throw EpubParseLimitException('EPUB 条目路径不安全: ${file.name}');
      }
      if (file.size < 0 || expandedBytes > _maxExpandedBytes - file.size) {
        throw const EpubParseLimitException('EPUB 总展开体积超过 1 GiB');
      }
      expandedBytes += file.size;
    }
    if (expandedBytes > _ratioCheckThresholdBytes &&
        compressedBytes > 0 &&
        expandedBytes > compressedBytes * _maxExpansionRatio) {
      throw const EpubParseLimitException('EPUB 压缩比超过安全上限');
    }
  }

  /// 安全读取归档条目字节。
  Uint8List _entryBytes(
    ArchiveFile entry, {
    int maxBytes = _maxTextEntryBytes,
  }) {
    if (entry.size < 0 || entry.size > maxBytes) {
      throw EpubParseLimitException('归档条目超过解析上限: ${entry.name}');
    }
    try {
      final content = entry.content;
      if (content.length > maxBytes) {
        throw EpubParseLimitException('归档条目解压后超过解析上限: ${entry.name}');
      }
      return content;
    } finally {
      entry.clear();
    }
  }

  /// 解析 container.xml 获取 OPF 路径
  String? _parseContainerXml(Uint8List bytes) {
    try {
      final doc = XmlDocument.parse(decodeEpubText(bytes));
      final rootfile = doc.findAllElements('rootfile').firstOrNull;
      return rootfile?.getAttribute('full-path');
    } on EpubParseLimitException {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        readerDebugLog('EPUB: container.xml parse failed: $e');
      }
      return null;
    }
  }

  /// 从 OPF 中提取 Dublin Core 元素
  String? _getDcElement(XmlDocument doc, String localName) {
    try {
      // 尝试带命名空间
      final elements = doc.findAllElements(
        localName,
        namespace: 'http://purl.org/dc/elements/1.1/',
      );
      if (elements.isNotEmpty) {
        return elements.first.innerText.trim();
      }
      // 回退：不带命名空间
      final fallback = doc.findAllElements('dc:$localName');
      if (fallback.isNotEmpty) {
        return fallback.first.innerText.trim();
      }
    } catch (error) {
      if (kDebugMode) {
        readerDebugLog('EPUB: _getDcElement($localName) failed: $error');
      }
    }
    return null;
  }

  /// 从 OPF 中提取封面图片
  Uint8List? _extractCover(
    XmlDocument opfDoc,
    Archive archive,
    String opfPath,
  ) {
    try {
      // EPUB2: <meta name="cover" content="cover-image-id"/>
      String? coverId;
      for (final meta in opfDoc.findAllElements('meta')) {
        if (meta.getAttribute('name')?.toLowerCase() == 'cover') {
          coverId = meta.getAttribute('content');
          break;
        }
      }

      // EPUB3: <item properties="cover-image" .../>
      if (coverId == null) {
        for (final item in opfDoc.findAllElements('item')) {
          final props = item.getAttribute('properties') ?? '';
          if (props.contains('cover-image')) {
            coverId = item.getAttribute('id');
            break;
          }
        }
      }

      if (coverId == null) return null;

      // 从 manifest 中查找 cover 的 href
      for (final item in opfDoc.findAllElements('item')) {
        if (item.getAttribute('id') == coverId) {
          final href = item.getAttribute('href');
          if (href == null || href.isEmpty) return null;

          final fullPath = _resolvePath(opfPath, href);
          final fileEntry = _findEntry(archive, fullPath);
          if (fileEntry != null) {
            if (kDebugMode) {
              readerDebugLog('EPUB: cover found at $fullPath');
            }
            return _entryBytes(fileEntry, maxBytes: _maxCoverBytes);
          }

          // 尝试 URL 解码
          final decodedPath = _resolvePath(opfPath, Uri.decodeComponent(href));
          final decodedEntry = _findEntry(archive, decodedPath);
          if (decodedEntry != null) {
            if (kDebugMode) {
              readerDebugLog('EPUB: cover found at decoded path $decodedPath');
            }
            return _entryBytes(decodedEntry, maxBytes: _maxCoverBytes);
          }

          if (kDebugMode) {
            readerDebugLog('EPUB: cover file not found: $fullPath');
          }
          return null;
        }
      }
    } on EpubParseLimitException {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        readerDebugLog('EPUB: cover extraction failed: $e');
      }
    }
    return null;
  }

  /// 构建 manifest 映射 (id → href)
  Map<String, String> _buildManifest(XmlDocument opfDoc) {
    final manifest = <String, String>{};
    for (final item in opfDoc.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id != null && href != null) {
        manifest[id] = href;
      }
    }
    return manifest;
  }

  /// 从 OPF spine 构建章节 href 列表
  List<String> _buildSpine(XmlDocument opfDoc, Map<String, String> manifest) {
    try {
      final spine = <String>[];
      for (final itemref in opfDoc.findAllElements('itemref')) {
        final idref = itemref.getAttribute('idref');
        if (idref != null && manifest.containsKey(idref)) {
          spine.add(manifest[idref]!);
        }
      }
      return spine;
    } catch (e) {
      if (kDebugMode) {
        readerDebugLog('EPUB: spine build failed: $e');
      }
      return [];
    }
  }

  // ── TOC 层级解析 ──

  /// 解析 TOC 文件获取章节层级映射。
  ///
  /// 返回 Map<相对href, level>，level 从 0 开始。
  /// 优先解析 EPUB3 nav.xhtml，回退到 EPUB2 toc.ncx。
  Map<String, int> _parseTocLevels(
    Archive archive,
    XmlDocument opfDoc,
    String opfPath,
  ) {
    // 尝试 EPUB3 nav.xhtml
    final navLevels = _parseNavToc(archive, opfDoc, opfPath);
    if (navLevels.isNotEmpty) return navLevels;

    // 回退到 EPUB2 toc.ncx
    final ncxLevels = _parseNcxToc(archive, opfDoc, opfPath);
    if (ncxLevels.isNotEmpty) return ncxLevels;

    return {};
  }

  /// 解析 EPUB3 nav.xhtml（<nav epub:type="toc">）
  Map<String, int> _parseNavToc(
    Archive archive,
    XmlDocument opfDoc,
    String opfPath,
  ) {
    try {
      // 从 manifest 中查找 nav 属性的 item
      String? navHref;
      for (final item in opfDoc.findAllElements('item')) {
        final properties = item.getAttribute('properties') ?? '';
        if (properties.contains('nav')) {
          navHref = item.getAttribute('href');
          break;
        }
      }
      if (navHref == null) return {};

      final navPath = _resolvePath(opfPath, navHref);
      final navEntry = _findEntry(archive, navPath);
      if (navEntry == null) return {};

      // nav 文件所在目录（用于解析 TOC 中的相对路径）
      final navDir = _parentDir(navPath);

      final navContent = decodeEpubText(_entryBytes(navEntry));
      final navDoc = XmlDocument.parse(navContent);

      // 找到 <nav epub:type="toc">
      final navElement = navDoc
          .findAllElements('nav')
          .firstWhere(
            (e) => (e.getAttribute('epub:type') ?? '').contains('toc'),
            orElse: () => navDoc.findAllElements('nav').first,
          );

      final rawLevels = <String, int>{};
      _walkNavOl(navElement, -1, rawLevels);

      // 将 TOC 相对路径转为完整路径（相对于 TOC 文件所在目录）
      final levels = <String, int>{};
      for (final entry in rawLevels.entries) {
        final fullPath = _resolvePath(navDir, entry.key);
        levels[fullPath] = entry.value;
      }
      if (kDebugMode) {
        readerDebugLog('EPUB: nav.xhtml parsed ${levels.length} entries');
        for (final entry in levels.entries) {
          readerDebugLog(
            '  ${'  ' * entry.value}[${entry.value}] ${entry.key}',
          );
        }
      }
      return levels;
    } on EpubParseLimitException {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        readerDebugLog('EPUB: nav.xhtml parse failed: $e');
      }
      return {};
    }
  }

  /// 递归遍历 nav.xhtml 的 <ol> 结构
  void _walkNavOl(XmlNode node, int level, Map<String, int> levels) {
    for (final child in node.childElements) {
      if (child.name.local == 'ol') {
        _walkNavOl(child, level + 1, levels);
      } else if (child.name.local == 'li') {
        final anchor = child.findElements('a').firstOrNull;
        if (anchor != null) {
          final href = anchor.getAttribute('href');
          if (href != null && href.isNotEmpty) {
            final cleanHref = href.split('#').first;
            levels[cleanHref] = level;
          }
        }
        _walkNavOl(child, level, levels);
      }
    }
  }

  /// 解析 EPUB2 toc.ncx（`<navMap>`/`<navPoint>`）
  Map<String, int> _parseNcxToc(
    Archive archive,
    XmlDocument opfDoc,
    String opfPath,
  ) {
    try {
      // 从 manifest 中查找 ncx 类型的 item
      String? ncxHref;
      for (final item in opfDoc.findAllElements('item')) {
        final mediaType = item.getAttribute('media-type') ?? '';
        if (mediaType == 'application/x-dtbncx+xml') {
          ncxHref = item.getAttribute('href');
          break;
        }
      }
      if (ncxHref == null) return {};

      final ncxPath = _resolvePath(opfPath, ncxHref);
      final ncxEntry = _findEntry(archive, ncxPath);
      if (ncxEntry == null) return {};

      // ncx 文件所在目录（用于解析 TOC 中的相对路径）
      final ncxDir = _parentDir(ncxPath);

      final ncxContent = decodeEpubText(_entryBytes(ncxEntry));
      final ncxDoc = XmlDocument.parse(ncxContent);

      final rawLevels = <String, int>{};
      final navMap = ncxDoc.findAllElements('navMap').firstOrNull;
      if (navMap != null) {
        _walkNavPoint(navMap, 0, rawLevels);
      }

      // 将 TOC 相对路径转为完整路径（相对于 NCX 文件所在目录）
      final levels = <String, int>{};
      for (final entry in rawLevels.entries) {
        final fullPath = _resolvePath(ncxDir, entry.key);
        levels[fullPath] = entry.value;
      }

      if (kDebugMode) {
        readerDebugLog('EPUB: toc.ncx parsed ${levels.length} entries');
        for (final entry in levels.entries) {
          readerDebugLog(
            '  ${'  ' * entry.value}[${entry.value}] ${entry.key}',
          );
        }
      }
      return levels;
    } on EpubParseLimitException {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        readerDebugLog('EPUB: toc.ncx parse failed: $e');
      }
      return {};
    }
  }

  /// 递归遍历 toc.ncx 的 `<navPoint>` 结构
  void _walkNavPoint(XmlNode node, int level, Map<String, int> levels) {
    for (final child in node.childElements) {
      if (child.name.local == 'navPoint') {
        final content = child.findElements('content').firstOrNull;
        if (content != null) {
          final src = content.getAttribute('src');
          if (src != null && src.isNotEmpty) {
            final cleanSrc = src.split('#').first;
            levels[cleanSrc] = level;
          }
        }
        _walkNavPoint(child, level + 1, levels);
      }
    }
  }

  /// 根据 href 查找 TOC 中的层级，回退到 0
  ///
  /// tocLevels 的 key 已经是完整路径（相对于 EPUB 根目录），
  /// spine href 需要解析为完整路径后比较。
  int _findTocLevel(Map<String, int> tocLevels, String href, String opfPath) {
    if (tocLevels.isEmpty) return 0;

    // 将 spine href 解析为完整路径
    final spineFullPath = _resolvePath(opfPath, href);

    // 直接匹配完整路径
    if (tocLevels.containsKey(spineFullPath)) return tocLevels[spineFullPath]!;

    // 模糊匹配：路径以 / + fileName 结尾，且前面也是 /（防止 3_02.xhtml 错配 3.xhtml）
    final fileName = href.split('/').last;
    for (final entry in tocLevels.entries) {
      final idx = entry.key.lastIndexOf('/$fileName');
      if (idx >= 0 && idx + 1 + fileName.length == entry.key.length) {
        // 验证文件名前的路径片段也一致（避免 3_02.xhtml 匹配到 3.xhtml）
        final spineParent = spineFullPath.lastIndexOf('/');
        final tocParent = idx;
        if (spineParent < 0 || tocParent < 0) return entry.value;
        final spineDir = spineFullPath.substring(0, spineParent);
        final tocDir = entry.key.substring(0, tocParent);
        if (spineDir == tocDir) return entry.value;
      }
    }

    if (kDebugMode) {
      readerDebugLog('EPUB: TOC miss for "$href" (resolved: $spineFullPath)');
    }
    return 0;
  }

  /// 从 HTML 中提取标题（第一个 h1-h6）
  String? _extractTitleFromHtml(String html) {
    try {
      // 用 regex 提取，不依赖 XML 解析（HTML 可能不是合法 XML）
      final match = RegExp(
        r'<h[1-6][^>]*>(.*?)</h[1-6]>',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(html);
      if (match != null) {
        final title = _stripHtml(match.group(1) ?? '').trim();
        if (title.isNotEmpty) return title;
      }
    } catch (error) {
      if (kDebugMode) {
        readerDebugLog('EPUB: _extractTitleFromHtml failed: $error');
      }
    }
    return null;
  }

  /// 解析相对路径
  String _resolvePath(String basePath, String relativePath) {
    final decoded = Uri.decodeComponent(relativePath);
    if (decoded.startsWith('/')) {
      return _normalizeArchivePath(decoded);
    }
    final normalizedBase = _normalizeArchivePath(basePath);
    final lastSlash = normalizedBase.lastIndexOf('/');
    final baseDirectory =
        lastSlash < 0 ? '' : normalizedBase.substring(0, lastSlash + 1);
    return _normalizeArchivePath('$baseDirectory$decoded');
  }

  String _normalizeArchivePath(String path) {
    final pathWithoutFragment = path
        .split('#')
        .first
        .split('?')
        .first
        .replaceAll('\\', '/');
    final resolved = <String>[];
    for (final part in pathWithoutFragment.split('/')) {
      if (part.isEmpty || part == '.') {
        continue;
      }
      if (part == '..') {
        if (resolved.isEmpty) {
          throw const FormatException('EPUB 归档路径越界');
        }
        resolved.removeLast();
        continue;
      }
      resolved.add(part);
    }
    return resolved.join('/');
  }

  /// 获取路径的父目录
  String _parentDir(String path) {
    final lastSlash = path.lastIndexOf('/');
    return lastSlash >= 0 ? path.substring(0, lastSlash + 1) : '';
  }

  /// 去除 HTML 标签，提取纯文本
  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'&[a-zA-Z]+;'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
