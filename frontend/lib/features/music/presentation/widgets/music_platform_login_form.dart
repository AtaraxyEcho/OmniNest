import 'package:flutter/material.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/presentation/widgets/music_platform_logged_in_card.dart';
import 'package:omninest/features/music/presentation/widgets/music_platform_qr_panel.dart';

/// 网易云登录区块：只保留扫码登录。
///
/// 手机号（密码 / 短信验证码）与邮箱登录已下线：平台授权统一走扫码确认，
/// 客户端不再收集平台密码与短信验证码，登录态只能通过扫码会话建立。
///
/// 不再嵌套 `MusicPlatformCard`：抽屉自身已带品牌头部（浅色为白色磨砂），
/// 再叠一层卡片会在浅色下形成"玻璃上贴灰卡"的配色割裂；内容直接落在
/// 抽屉底面上，与样例的层级一致。
class NeteaseLoginSection extends StatelessWidget {
  const NeteaseLoginSection({required this.userInfo, super.key});

  final PlatformUserInfo? userInfo;

  @override
  Widget build(BuildContext context) {
    final user = userInfo;
    return user != null
        ? MusicPlatformLoggedInCard(
          user: user,
          accentColor: const Color(0xFFEC4141),
        )
        : const MusicPlatformQrPanel();
  }
}
