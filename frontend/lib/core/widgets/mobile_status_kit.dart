import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';

/// 状态丸色调：对应原型 `.status-pill` 的 calm / warning / danger 三档。
enum MobileStatusTone { calm, warning, danger }

/// 传输页三档色调的具体取值。
///
/// calm 档走强调色的"墨"角色（文字与其软填充同一角色），warning/danger 是彩性色，
/// 两极性保持原值。
Color _statusForeground(MobileEnvPalette env, MobileStatusTone tone) {
  return switch (tone) {
    MobileStatusTone.calm => env.accentInk,
    MobileStatusTone.warning => const Color(0xFFE9BD7C),
    MobileStatusTone.danger => const Color(0xFFE69696),
  };
}

Color _statusBackground(MobileEnvPalette env, MobileStatusTone tone) {
  return switch (tone) {
    MobileStatusTone.calm => env.accentInk.withValues(alpha: 0.08),
    MobileStatusTone.warning => const Color(0x1FD18A34),
    MobileStatusTone.danger => const Color(0x1FDA5050),
  };
}

/// 原型 `.status-pill`：23 高、r8、7px 大写宽字距状态丸。
class MobileStatusPill extends StatelessWidget {
  const MobileStatusPill({
    required this.label,
    this.tone = MobileStatusTone.calm,
    super.key,
  });

  final String label;
  final MobileStatusTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 23),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: _statusBackground(context.env, tone),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 7, // ignore: font_size_whitelist
          letterSpacing: 0.7,
          fontWeight: FontWeight.w800,
          color: _statusForeground(context.env, tone),
        ),
      ),
    );
  }
}

/// 原型 `.transfer-row`：42 图标舱 + 名称/明细 + 3px 进度 + 右侧状态丸。
class MobileTransferRow extends StatelessWidget {
  const MobileTransferRow({
    required this.title,
    required this.detail,
    required this.icon,
    super.key,
    this.progress,
    this.statusLabel,
    this.tone = MobileStatusTone.calm,
    this.onTap,
  });

  final String title;
  final String detail;
  final OmniIconsData icon;

  /// 0-1 进度；null 时不画进度条。
  final double? progress;
  final String? statusLabel;
  final MobileStatusTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.env.line07)),
      ),
      child: Row(
        children: [
          _StatusIconTile(icon: icon, tone: tone),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.env.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9, // ignore: font_size_whitelist
                    color: context.env.inkMuted,
                  ),
                ),
                if (progress != null) ...[
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress!.clamp(0, 1),
                      minHeight: 3,
                      backgroundColor: const Color(0x1AFFFFFF),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        context.env.accentInk,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (statusLabel != null)
            MobileStatusPill(label: statusLabel!, tone: tone),
        ],
      ),
    );
    if (onTap == null) {
      return row;
    }
    return MobilePressable(semanticLabel: title, onTap: onTap, child: row);
  }
}

/// 原型 `.transfer-summary`：三格摘要（衬线 21 数值 + 7px 眉标）。
class MobileTransferSummary extends StatelessWidget {
  const MobileTransferSummary({required this.entries, super.key});

  final List<MobileTransferSummaryEntry> entries;

  @override
  Widget build(BuildContext context) {
    // 均分用 Expanded，交叉轴不取 stretch：本组件常被放进 Column，
    // stretch 会把无限高传给子级并触发约束断言。
    return Row(
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          if (index > 0) const SizedBox(width: 7),
          Expanded(child: _SummaryCell(entry: entries[index])),
        ],
      ],
    );
  }
}

/// 摘要格内容。
class MobileTransferSummaryEntry {
  const MobileTransferSummaryEntry({required this.value, required this.label});

  final String value;
  final String label;
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({required this.entry});

  final MobileTransferSummaryEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 69),
      padding: const EdgeInsets.all(10),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: const Color(0x0CFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.env.line07),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTypography.serifFamily,
              fontFamilyFallback: AppTypography.serifFamilyFallback,
              fontSize: 21, // ignore: font_size_whitelist
              fontWeight: FontWeight.w400,
              color: context.env.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            entry.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 7, // ignore: font_size_whitelist
              letterSpacing: 1,
              color: context.env.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// 原型 `.disabled-card` / `.connection-check`：62 高条件说明条 + 右侧行动。
class MobileDisabledCard extends StatelessWidget {
  const MobileDisabledCard({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
    this.actionLabel,
    this.onAction,
    this.positive = false,
  });

  final OmniIconsData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// 通过态用对勾酸绿，受阻态用弱化前景。
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: context.env.line07),
      ),
      child: Row(
        children: [
          OmniIcon(
            icon: icon,
            size: 17,
            color: positive ? context.env.accentInk : context.env.inkMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: context.env.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8, // ignore: font_size_whitelist
                    height: 1.4,
                    color: context.env.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 10),
            MobilePressable(
              semanticLabel: actionLabel!,
              onTap: onAction,
              child: Container(
                constraints: const BoxConstraints(minHeight: 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0x12FFFFFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  actionLabel!,
                  style: TextStyle(
                    fontSize: 9, // ignore: font_size_whitelist
                    color: context.env.ink,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 原型 `.offline-banner`：42 高琥珀条件条，全局仅在壳层挂一条。
class MobileOfflineBanner extends StatelessWidget {
  const MobileOfflineBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 42),
      margin: const EdgeInsets.fromLTRB(0, 10, 0, 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0x1FD18A34),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x47D18A34)),
      ),
      child: Row(
        children: [
          const OmniIcon(
            icon: OmniIcons.cloud,
            size: 16,
            color: Color(0xFFE9BD7C),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 9, // ignore: font_size_whitelist
                height: 1.4,
                color: Color(0xFFE9BD7C),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusIconTile extends StatelessWidget {
  const _StatusIconTile({required this.icon, required this.tone});

  final OmniIconsData icon;
  final MobileStatusTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: _statusBackground(context.env, tone),
        borderRadius: BorderRadius.circular(13),
      ),
      alignment: Alignment.center,
      child: OmniIcon(
        icon: icon,
        size: 18,
        color: _statusForeground(context.env, tone),
      ),
    );
  }
}
