/// 通用安全存储抽象接口。
/// 当前认证存储通过 [AuthSessionStore] 的平台实现完成，
/// 此接口保留作为其他安全数据存储的扩展点。
abstract interface class SecureStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}
