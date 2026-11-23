part of 'desktop_np_style.dart';

/// 将颜色编码为标准 `#RRGGBB` 大写十六进制字符串。
String colorToHex(Color color) {
  final r = (color.r * 255)
      .round()
      .clamp(0, 255)
      .toRadixString(16)
      .padLeft(2, '0');
  final g = (color.g * 255)
      .round()
      .clamp(0, 255)
      .toRadixString(16)
      .padLeft(2, '0');
  final b = (color.b * 255)
      .round()
      .clamp(0, 255)
      .toRadixString(16)
      .padLeft(2, '0');
  return '#$r$g$b'.toUpperCase();
}

/// 解析 `#RGB` 或 `#RRGGBB` 字符串为不透明 [Color]。
Color? parseHexColor(String? raw) {
  if (raw == null) return null;
  var text = raw.trim();
  if (text.startsWith('#')) {
    text = text.substring(1);
  }
  if (text.length == 3 && RegExp(r'^[0-9a-fA-F]{3}$').hasMatch(text)) {
    text = '${text[0]}${text[0]}${text[1]}${text[1]}${text[2]}${text[2]}';
  }
  if (text.length != 6 || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(text)) {
    return null;
  }
  final value = int.tryParse(text, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

final desktopNpStyleProvider =
    NotifierProvider<DesktopNpStyleController, DesktopNpStyle>(
      DesktopNpStyleController.new,
    );

/// 正在播放页样式控制器：本地 SharedPreferences 快速加载，已认证时异步拉取
/// 服务端 `music_now_playing` 偏好合并，变更时防抖异步推送服务端。
class DesktopNpStyleController extends Notifier<DesktopNpStyle> {
  static const _key = 'omninest.desktop.npStyle';
  static const _syncDebounce = Duration(milliseconds: 300);

  bool _loaded = false;
  Future<void>? _loadFuture;
  int _localMutationVersion = 0;
  String? _activeUserId;
  String? _lastBoundUserId;
  int _loadGeneration = 0;
  Timer? _syncDebounceTimer;
  DesktopNpStyle? _pendingRemoteStyle;

  @override
  DesktopNpStyle build() {
    ref.onDispose(() {
      _syncDebounceTimer?.cancel();
      _syncDebounceTimer = null;
      _pendingRemoteStyle = null;
    });
    try {
      ref.listen(authSessionProvider, (_, next) {
        final userId = next.value?.user?.id;
        unawaited(_bindUser(userId));
      }, fireImmediately: true);
    } on Object {
      // 测试或离线环境未注入认证会话时静默回退本地偏好。
    }
    return const DesktopNpStyle();
  }

  Future<void> load() {
    if (_loaded) {
      return Future<void>.value();
    }
    return _loadFuture ??= _performLoad();
  }

  Future<void> _performLoad() async {
    final mutationVersionAtStart = _localMutationVersion;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted) {
        return;
      }
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, Object?> &&
              _localMutationVersion == mutationVersionAtStart &&
              ref.mounted) {
            state = DesktopNpStyle.fromJson(decoded);
          }
        } on FormatException {
          // 旧版本或手改坏的偏好直接回落到默认，不阻塞播放页。
        }
      }
      _loaded = true;
    } finally {
      _loadFuture = null;
    }
  }

  Future<void> apply(DesktopNpStyle next) async {
    if (!ref.mounted) {
      return;
    }
    _localMutationVersion++;
    state = next;
    await _writeLocal(next);
    if (!ref.mounted) {
      return;
    }
    _scheduleRemotePatch(next);
  }

  Future<void> reset() => apply(const DesktopNpStyle());

  /// 从远端重新同步正在播放页样式偏好，并保留本地待提交变更。
  Future<void> refreshFromRemote() async {
    if (!ref.mounted) {
      return;
    }
    final userId = _activeUserId;
    final service = _tryReadSyncService();
    if (userId == null || service == null) return;
    try {
      final snapshot = await service.synchronize(
        userId: userId,
        scope: desktopNpStylePreferenceScope,
      );
      if (!ref.mounted ||
          _activeUserId != userId ||
          snapshot.preferences.isEmpty) {
        return;
      }
      final resolved = DesktopNpStyle.fromJson(snapshot.preferences);
      state = resolved;
      await _writeLocal(resolved);
    } on Object {
      // 离线或远端不可用时静默保留本地偏好。
    }
  }

  Future<void> _bindUser(String? userId) async {
    if (!ref.mounted) {
      return;
    }
    final previousUserId = _lastBoundUserId;
    _activeUserId = userId;
    final generation = ++_loadGeneration;
    await load();
    if (!ref.mounted ||
        generation != _loadGeneration ||
        _activeUserId != userId) {
      return;
    }
    if (userId == null) {
      _syncDebounceTimer?.cancel();
      _pendingRemoteStyle = null;
      return;
    }

    final service = _tryReadSyncService();
    if (service == null) {
      return;
    }
    try {
      final snapshot = await service.load(
        userId: userId,
        scope: desktopNpStylePreferenceScope,
      );
      if (!ref.mounted ||
          generation != _loadGeneration ||
          _activeUserId != userId) {
        return;
      }
      if (snapshot.preferences.isEmpty) {
        final switchedAccount =
            previousUserId != null && previousUserId != userId;
        _lastBoundUserId = userId;
        if (switchedAccount) {
          return;
        }
        await service.patch(
          userId: userId,
          scope: desktopNpStylePreferenceScope,
          changes: Map<String, dynamic>.from(state.toJson()),
        );
        return;
      }
      _lastBoundUserId = userId;
      final resolved = DesktopNpStyle.fromJson(snapshot.preferences);
      state = resolved;
      await _writeLocal(resolved);
    } on Object {
      // 离线或无同步依赖注入时静默保留本地偏好。
    }
  }

  void _scheduleRemotePatch(DesktopNpStyle next) {
    final userId = _activeUserId;
    if (userId == null) {
      return;
    }
    _pendingRemoteStyle = next;
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(_syncDebounce, () {
      if (!ref.mounted) {
        return;
      }
      unawaited(_flushRemotePatch(userId));
    });
  }

  Future<void> _flushRemotePatch(String userId) async {
    if (!ref.mounted) {
      return;
    }
    final pending = _pendingRemoteStyle;
    if (_activeUserId != userId || pending == null) {
      return;
    }
    _pendingRemoteStyle = null;
    final service = _tryReadSyncService();
    if (service == null) {
      return;
    }
    try {
      await service.patch(
        userId: userId,
        scope: desktopNpStylePreferenceScope,
        changes: Map<String, dynamic>.from(pending.toJson()),
      );
    } on Object {
      // 离线或远端失败时静默保留本地配置，由 pending 与下次同步收敛。
    }
  }

  PreferenceSyncService? _tryReadSyncService() {
    if (!ref.mounted) {
      return null;
    }
    try {
      return ref.read(preferenceSyncServiceProvider);
    } on Object {
      return null;
    }
  }

  Future<void> _writeLocal(DesktopNpStyle style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(style.toJson()));
  }
}
