import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// 打开 Web 平台 SQLite 数据库连接。
QueryExecutor openConnection() {
  return DatabaseConnection.delayed(
    Future(() async {
      final result = await WasmDatabase.open(
        databaseName: 'omninest_cache',
        // 相对页面基准解析，支持部署在反代子路径下（--base-href）。
        sqlite3Uri: Uri.base.resolve('sqlite3.wasm'),
        driftWorkerUri: Uri.base.resolve('drift_worker.js'),
      );
      return result.resolvedExecutor;
    }),
  );
}
