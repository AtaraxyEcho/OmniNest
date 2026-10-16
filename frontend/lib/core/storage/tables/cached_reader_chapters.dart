import 'package:drift/drift.dart';

/// 本地缓存的章节内容表。
///
/// 存储从 EPUB 提取并预处理后的 XHTML 内容，
/// 避免每次打开章节都重新从 ZIP 提取和 base64 编码图片。
///
/// [userId] 与书级样式表池同口径进入主键：`processed_html` 与
/// `stylesheet_refs_json` 用当前登录用户的密钥加密，不归户就会让换号后的
/// 账号命中上一个账号的密文并解密失败。
class CachedReaderChapters extends Table {
  TextColumn get userId => text().withDefault(const Constant(''))();

  /// 书籍条目 ID
  TextColumn get itemId => text()();

  /// 章节内容路径（EPUB 内部路径，如 OEBPS/chapter1.xhtml）
  TextColumn get contentPath => text()();

  /// 章节标题
  TextColumn get title => text().withDefault(const Constant(''))();

  /// 章节序号
  IntColumn get chapterNumber => integer().withDefault(const Constant(0))();

  /// 原始 XHTML 字符数
  IntColumn get charCount => integer().withDefault(const Constant(0))();

  /// 预处理后的 HTML 内容（已提取 body、图片已转 base64）
  TextColumn get processedHtml => text()();

  /// 本章生效的样式表次序 JSON（归档内路径列表，指向书级池的键）。
  ///
  /// 次序取自本章 head 里 `<link>` 的书写顺序，link 没提到的表按 manifest 序补在
  /// 后面；EPUB 的层叠胜负依赖它，所以必须按章存而不是整本书共用一份次序。
  /// 空列表表示本章没有样式表可生效。
  TextColumn get stylesheetRefsJson =>
      text().withDefault(const Constant('[]'))();

  /// 缓存创建时间
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {userId, itemId, contentPath};
}
