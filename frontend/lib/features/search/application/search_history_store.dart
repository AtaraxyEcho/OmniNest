import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 搜索历史存储的应用层入口。
final searchHistoryStoreProvider = Provider<SearchHistoryStore>((ref) {
  return const SearchHistoryStore();
});

/// 搜索历史的本地持久化。
///
/// 键由调用方按用户维度计算，这一层只负责读写：面板关闭后写盘回调仍在跑，
/// 若把会话读取一并放进来，就会在卸载之后才碰 ref。
class SearchHistoryStore {
  const SearchHistoryStore();

  Future<List<String>> load(String storageKey) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getStringList(storageKey) ?? const <String>[];
  }

  Future<void> save(String storageKey, List<String> values) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(storageKey, values);
  }
}
