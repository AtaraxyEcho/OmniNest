import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 详情页统一退出入口：优先 pop 保留上级 shell 状态，无栈时兜底 go 到指定路由。
void exitDetailRoute(BuildContext context, {required String fallbackRoute}) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallbackRoute);
  }
}
