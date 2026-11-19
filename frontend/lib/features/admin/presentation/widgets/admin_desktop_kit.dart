import 'package:flutter/widgets.dart';

import 'package:omninest/app/desktop/widgets/desktop_pager.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';

/// 管理台桌面分区的共用骨架（样例 `desktop.css` 的 `.card` / `.adm-stats` /
/// `.pager`）。各分区只写内容，卡片内距、标题阶梯与翻页条几何都在这里，
/// 避免十个分区各画一层容器后逐渐走样。
class AdminCard extends StatelessWidget {
  const AdminCard({
    required this.title,
    required this.child,
    this.count,
    this.subtitle,
    this.action,
    this.childGap = 12,
    super.key,
  });

  final String title;

  /// 标题后的计数（样例 `Users · 12` 的灰色小字）。
  final int? count;

  /// 标题下的说明文字，样例用 `.muted` 段落。
  final String? subtitle;

  final Widget? action;
  final Widget child;

  /// 标题区与内容之间的间距；表格类内容用 14，纯文本用 12。
  final double childGap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      // 样例 `.card { padding: 22px 24px }`。
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        // 原型 `.card` 使用半透明 panel；`raise` 会让管理页在背景库
        // 开启时退化成几乎不见的深色块，浅色主题也失去层次。
        color: skin.panel,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
        border: Border.all(color: skin.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: title,
                    style: DesktopType.cardTitle(skin.text),
                    children: [
                      if (count != null)
                        TextSpan(
                          text: ' · $count',
                          style: DesktopType.caption(skin.text3),
                        ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (action != null) ...[const SizedBox(width: 12), action!],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, style: DesktopType.caption(skin.text3)),
          ],
          SizedBox(height: childGap),
          child,
        ],
      ),
    );
  }
}

/// 指标卡：眉标 + 衬线数值 + 提示（样例 `.adm-stats .card`）。
class AdminStatCard extends StatelessWidget {
  const AdminStatCard({
    required this.label,
    required this.value,
    required this.hint,
    super.key,
  });

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
        border: Border.all(color: skin.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: DesktopType.eyebrow(skin.text3)),
          const SizedBox(height: 8),
          Text(value, style: DesktopType.adminStatValue(skin.text)),
          const SizedBox(height: 2),
          Text(
            hint,
            style: DesktopType.caption(skin.text3),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// 翻页条：左侧计数、右侧首/前/页码/后/末（样例 `.pager` + `.pg-b`）。
/// 结构在共享控件 [DesktopPager] 里，管理台只负责套上分隔线与间距。
class AdminPager extends StatelessWidget {
  const AdminPager({
    required this.page,
    required this.totalPages,
    required this.summary,
    required this.onPageChanged,
    super.key,
  });

  /// 从 0 开始的页码，与各控制器的 `state.page` 一致。
  final int page;
  final int totalPages;
  final String summary;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    // 顶部发丝线、上边距与换行都在 DesktopPager 里（样例 `.pager`）。
    return DesktopPager(
      page: page,
      totalPages: totalPages,
      summary: summary,
      onPageChanged: onPageChanged,
    );
  }
}
