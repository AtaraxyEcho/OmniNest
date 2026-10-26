/// 语义化版本比较。
///
/// 客户端与服务端配置的版本号只按 `major.minor.patch` 比较数字段；
/// 预发布后缀（`-beta.1`）与构建号（`+12`）不参与比较，与"是否已是最新"的产品语义一致。
library;

/// 判断 [remote] 是否严格新于 [local]。
///
/// 任一版本无法解析时退回字符串不等判断，保持旧行为（宁可提示更新）。
bool isNewerVersion(String remote, String local) {
  final remoteParts = parseSemver(remote);
  final localParts = parseSemver(local);
  if (remoteParts == null || localParts == null) {
    return remote.trim() != local.trim();
  }
  for (var index = 0; index < 3; index++) {
    if (remoteParts[index] != localParts[index]) {
      return remoteParts[index] > localParts[index];
    }
  }
  return false;
}

/// 解析 `v1.2.3-beta+build` 形式的版本号，缺失段按 0 处理。
List<int>? parseSemver(String version) {
  var text = version.trim();
  if (text.startsWith('v') || text.startsWith('V')) {
    text = text.substring(1);
  }
  final cutoff = text.indexOf(RegExp(r'[-+]'));
  if (cutoff >= 0) {
    text = text.substring(0, cutoff);
  }
  if (text.isEmpty) {
    return null;
  }
  final segments = text.split('.');
  final parts = <int>[0, 0, 0];
  for (var index = 0; index < segments.length && index < 3; index++) {
    final value = int.tryParse(segments[index]);
    if (value == null) {
      return null;
    }
    parts[index] = value;
  }
  return parts;
}
