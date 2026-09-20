import 'package:flutter/material.dart';

/// 认证/安装检查在途时的停泊页：受保护路由在会话恢复完成前不构建，
/// 避免未携带凭据的首批业务请求触发 401 风暴。
class BootPage extends StatelessWidget {
  const BootPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
