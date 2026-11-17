import 'package:drift/drift.dart';

/// 应用本机背景素材表。
@DataClassName('AppBackdropAssetRow')
class AppBackdropAssets extends Table {
  @override
  String get tableName => 'app_backdrop_assets';

  /// 本机背景素材 ID。
  TextColumn get id => text()();

  /// 本机文件绝对路径。
  TextColumn get path => text()();

  /// 展示名称。
  TextColumn get title => text()();

  /// 媒体类型：image、gif、video。
  TextColumn get mediaType => text()();

  /// 来源类型：file、directory。
  TextColumn get sourceType => text()();

  /// 来源目录路径。
  TextColumn get sourceDirectory => text().nullable()();

  /// 文件大小，单位字节。
  IntColumn get fileSize => integer().withDefault(const Constant(0))();

  /// 文件最后修改时间。
  DateTimeColumn get modifiedAt => dateTime()();

  /// 图片或视频宽度，尚未解析时为空。
  IntColumn get width => integer().nullable()();

  /// 图片或视频高度，尚未解析时为空。
  IntColumn get height => integer().nullable()();

  /// 视频时长，单位毫秒，非视频为空。
  IntColumn get durationMs => integer().nullable()();

  /// 服务端探测的视频编码名，图片与探测失败时为空。
  TextColumn get videoCodec => text().nullable()();

  /// 视频在 Web 客户端是否可解码，编码未知时按可播处理。
  BoolColumn get webPlayable => boolean().withDefault(const Constant(true))();

  /// 本机缩略图缓存路径。
  TextColumn get thumbnailPath => text().nullable()();

  /// 文件是否已缺失。
  BoolColumn get missing => boolean().withDefault(const Constant(false))();

  /// 服务端生命周期状态：READY / PROCESSING / FAILED；内置素材恒为 READY。
  TextColumn get status => text().withDefault(const Constant('READY'))();

  /// 创建时间。
  DateTimeColumn get createdAt => dateTime()();

  /// 更新时间。
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
