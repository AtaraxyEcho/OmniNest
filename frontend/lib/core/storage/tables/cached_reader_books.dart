import 'package:drift/drift.dart';

/// 本地缓存的书籍元数据表。
///
/// 存储 EPUB/TXT 解析后的元数据和章节目录，
/// 避免每次打开书籍都重新解析。
///
/// [userId] 是缓存归属账号并进入主键：`stylesheet_pool_json` 与章节切片按当前
/// 登录用户的密钥加密，共享书籍在不同账号下复用同一个 itemId，不归户就会让
/// 换号后的账号命中上一个账号的密文并解密失败。
class CachedReaderBooks extends Table {
  TextColumn get userId => text().withDefault(const Constant(''))();

  /// 书籍条目 ID
  TextColumn get itemId => text()();

  /// 书籍标题
  TextColumn get title => text().nullable()();

  /// 作者
  TextColumn get author => text().nullable()();

  /// 简介
  TextColumn get description => text().nullable()();

  /// 出版社
  TextColumn get publisher => text().nullable()();

  /// 语言
  TextColumn get language => text().nullable()();

  /// 章节列表 JSON（List<Map>，含 number/title/charCount/contentPath）
  TextColumn get chaptersJson => text().withDefault(const Constant('[]'))();

  /// 这本书声明的样式表池 JSON（归档内路径 → CSS 文本，按 manifest 顺序）。
  ///
  /// 一本书一份，随首次章节 ingest 写入；章节行只带自己那份次序引用
  /// （`cached_reader_chapters.stylesheet_refs_json`）。旧行为 `'{}'`：那类章节正文
  /// 里自带 `<style>` 载体，解析侧的内联通路照样读得到，不需要兼容写法。
  TextColumn get stylesheetPoolJson =>
      text().withDefault(const Constant('{}'))();

  /// 总字符数
  IntColumn get totalChars => integer().withDefault(const Constant(0))();

  /// 文件类型（EPUB/TXT/PDF）
  TextColumn get itemType => text().withDefault(const Constant('EPUB'))();

  /// 缓存版本指纹（条目 updatedAt）。
  ///
  /// 服务端重新解析会更新条目 updatedAt；版本不符时丢弃元数据与章节
  /// 切片缓存，避免 TXT 字符偏移变化后继续命中错位的旧章节内容。
  TextColumn get cacheVersion => text().withDefault(const Constant(''))();

  /// 缓存创建时间
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {userId, itemId};
}
