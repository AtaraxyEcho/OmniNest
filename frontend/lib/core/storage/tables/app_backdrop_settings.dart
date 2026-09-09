import 'package:drift/drift.dart';

/// 应用本机背景设置表。
@DataClassName('AppBackdropSettingRow')
class AppBackdropSettingsTable extends Table {
  @override
  String get tableName => 'app_backdrop_settings';

  /// 设置作用域，当前固定为 application。
  TextColumn get id => text()();

  /// 是否启用本机背景。
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();

  /// 当前选中的本机背景素材 ID。
  TextColumn get selectedBackdropId => text().nullable()();

  /// 桌面端和移动端是否分别使用独立背景选择。
  BoolColumn get separateDeviceBackdrops =>
      boolean().withDefault(const Constant(false))();

  /// 桌面端选中的本机背景素材 ID。
  TextColumn get desktopBackdropId => text().nullable()();

  /// 移动端选中的本机背景素材 ID。
  TextColumn get mobileBackdropId => text().nullable()();

  /// 背景适配方式：cover、contain、fill。
  TextColumn get fit => text().withDefault(const Constant('cover'))();

  /// cover/fill 对齐：top、center、bottom。
  TextColumn get alignment => text().withDefault(const Constant('center'))();

  /// 背景暗化强度。
  RealColumn get dimAmount => real().withDefault(const Constant(0.16))();

  /// 背景模糊强度。
  RealColumn get blurAmount => real().withDefault(const Constant(0.0))();

  /// 视频背景是否静音。
  BoolColumn get videoMuted => boolean().withDefault(const Constant(true))();

  /// 更新时间。
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
