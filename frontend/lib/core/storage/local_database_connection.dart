import 'package:drift/drift.dart';

/// 当前平台不支持本地数据库连接。
QueryExecutor openConnection() {
  throw UnsupportedError('当前平台不支持本地 SQLite 数据库');
}
