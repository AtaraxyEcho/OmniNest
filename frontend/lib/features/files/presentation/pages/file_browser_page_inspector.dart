part of 'file_browser_page.dart';

/// 桌面详情检视栏：220ms 平滑开合，≥1920 常驻并排、中屏侧滑。
///
/// Esc 清空检视态；关闭按钮同样清空选中条目（规范 Toggle 语义）。
class _InspectorDock extends ConsumerWidget {
  const _InspectorDock({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final node = state.inspectedNode;
    return AnimatedContainer(
      duration: MotionToken.resolve(context, MotionToken.pageSwitch),
      curve: Curves.easeOutCubic,
      width: state.inspectorOpen ? 320 : 0,
      child: ClipRect(
        child: SizedBox(
          width: 320,
          child: Container(
            decoration: BoxDecoration(
              color: context.filesColors.surfaceContainerLow,
              border: Border(
                left: BorderSide(color: context.filesColors.outlineVariant),
              ),
            ),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape):
                    () => controller.clearInspection(),
              },
              child:
                  node == null
                      ? _InspectorEmptyHint(
                        onOpen: () => controller.toggleInspector(),
                      )
                      : FileInspectorPanel(
                        file: node,
                        actions: _buildFileNodeActions(
                          context,
                          ref,
                          controller,
                          recycle:
                              state.section == FileManagerSection.recycleBin,
                          favorites:
                              state.section == FileManagerSection.favorites,
                        ),
                        onClose: controller.clearInspection,
                      ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InspectorEmptyHint extends StatelessWidget {
  const _InspectorEmptyHint({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.view_sidebar_outlined,
              size: 28,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              AppLocalizations.of(context).filesInspectorEmptyHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppTypography.bodySmall,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
