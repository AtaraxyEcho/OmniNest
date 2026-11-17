import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Web 平台没有托盘：空绑定，保持与 IO 变体同名同型。
final desktopTrayLocaleBindingProvider = Provider<void>((ref) {});
