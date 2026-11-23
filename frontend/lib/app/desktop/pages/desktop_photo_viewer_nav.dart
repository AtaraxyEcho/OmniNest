part of 'desktop_photo_viewer_page.dart';

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.alignment,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Alignment alignment;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        // 样例 `.vw-nav`：52×52 圆钮、图标 26、左右各 20 边距。
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: DesktopIconButton(
          icon: icon,
          size: 52,
          iconSize: 26,
          tooltip: tooltip,
          onPressed: onPressed,
        ),
      ),
    );
  }
}
