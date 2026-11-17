import 'package:flutter/material.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';

/// 标记当前子树渲染于移动端工位底部面板内。
///
/// [WorkstationDialogFrame] 读取该标记后切换为无边框的 sheet 分区形态
/// （把手、顶部圆角与面板底色由本面板承担，框架只保留内容结构）。
class WorkstationSheetAmbient extends InheritedWidget {
  const WorkstationSheetAmbient({required super.child, super.key});

  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkstationSheetAmbient>() !=
      null;

  @override
  bool updateShouldNotify(WorkstationSheetAmbient oldWidget) => false;
}

/// 工位弹窗的移动端形态：底部玻璃面板（把手 + 顶部圆角 + 发丝顶线）。
///
/// 由 `showWorkstationDialog` 在 MobileShellScope 托管态自动分流调用，
/// 调用方与桌面路径共用同一 builder 与返回值语义。面板手机全幅、
/// ≥600 限宽 520 居中，高度封顶 85% 视口，键盘弹起随 viewInsets 抬升；
/// 在面板内再次打开工位弹窗时由路由栈自然叠加，上层面板覆盖下层。
Future<T?> showWorkstationMobileSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
  bool useRootNavigator = true,
}) {
  // 根导航路由会逃逸移动壳层的暗色 Theme：在调用点捕获宿主主题并在
  // 面板内重建，保证浅色根主题下 sheet 内容不会翻白。
  final ambientTheme = Theme.of(context);
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: Colors.transparent,
    barrierColor: MobileEnvPalette.of(context).modalScrim,
    builder: (sheetContext) {
      return Theme(
        data: ambientTheme,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Align(
            // 限宽后面板必须显式沉底：ModalBottomSheet 的默认定位会在
            // maxWidth 约束下面板浮到视口中部。
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 520,
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.env.sheetSolid,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    border: Border(top: BorderSide(color: context.env.line13)),
                    boxShadow: [
                      BoxShadow(
                        color: context.env.sheetGlow,
                        blurRadius: 50,
                        offset: const Offset(0, -20),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: WorkstationSheetAmbient(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const WorkstationSheetHandle(),
                          // builder 的入参 context 位于其返回子树的上方，
                          // 必须在 Ambient 内再垫一层 Builder，使调用方拿到的
                          // context 能向上查到 Ambient（二级弹窗维持 sheet 形态）。
                          Flexible(
                            child: Builder(
                              builder:
                                  (contentContext) => builder(contentContext),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// 面板顶部自绘把手（36×4 白 22%），与账户面板同规格。
class WorkstationSheetHandle extends StatelessWidget {
  const WorkstationSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        key: const ValueKey<String>('workstation-sheet-handle'),
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 14),
        decoration: BoxDecoration(
          color: context.env.line25,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
