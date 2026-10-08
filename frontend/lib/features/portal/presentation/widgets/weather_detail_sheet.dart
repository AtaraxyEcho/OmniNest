import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/app/mobile_shell/mobile_environment_scope.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';

/// 天气详情底部面板（原型 WeatherDetail 逐值复刻）。
///
/// 结构：场景图头（壁纸 → 视频缩略图 → 打包兜底，恒有图）→「{城市} ·
/// 本地天气」眉标 + 衬线天况标题 → 当前大字温度 → 逐时横轨 → 2×2 指标格
/// → 三日预报 → 环境跟随尾注。7-9px 微型字号为样例签名密度，逐行登记
/// font_size_whitelist 豁免。
/// 打开天气详情面板（样例 modal-layer 逐值复刻）。
///
/// 样例是全屏 fixed 层：blur(8px) 遮罩 + rgba(0,0,0,.45) 压暗淡入，
/// 面板从屏幕底部上滑锚定（覆盖顶栏/底栏）。宿主分支使用嵌套
/// Navigator，必须推入根 Navigator，否则遮罩只盖住分支视口、面板被
/// 压缩在底栏之上（内容顶部被裁）。
Future<void> showWeatherDetailSheet(
  BuildContext ownerContext, {
  required WeatherData weather,
}) {
  return Navigator.of(
    ownerContext,
    rootNavigator: true,
  ).push(_WeatherSheetRoute(weather: weather));
}

/// 天气面板路由：遮罩淡入（.2s）+ 面板上滑（.3s），均可用系统返回关闭。
class _WeatherSheetRoute extends PopupRoute<void> {
  _WeatherSheetRoute({required this.weather});

  final WeatherData weather;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => null;

  /// 保持下方页面存活：遮罩的 BackdropFilter 需要取到壳层环境像素。
  @override
  bool get opaque => false;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeIn,
    );
    final closeTooltip = MaterialLocalizations.of(context).closeButtonTooltip;
    return Stack(
      children: [
        // 样例遮罩：先 blur(8px) 再压 rgba(0,0,0,.45)，点击关闭。
        Positioned.fill(
          child: Semantics(
            button: true,
            label: closeTooltip,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: DecoratedBoxTransition(
                    decoration: DecorationTween(
                      begin: const BoxDecoration(color: Colors.transparent),
                      end: const BoxDecoration(color: Color(0x73000000)),
                    ).animate(curved),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: _WeatherDragDismissSheet(weather: weather),
          ),
        ),
      ],
    );
  }
}

/// 面板容器：承接垂直拖拽（下拉关闭），替代系统 BottomSheet 手势。
class _WeatherDragDismissSheet extends StatelessWidget {
  const _WeatherDragDismissSheet({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    // 面板经 PopupRoute 推入，可能挂在 root navigator 上而拿不到首页子树的极性注册，
    // 所以自带一份；取值仍是全局壁纸极性，不是明暗设置。
    return MobileEnvironmentScope(
      child: GestureDetector(
        onVerticalDragEnd:
            (details) => _maybeDismiss(context, details.primaryVelocity),
        child: _WeatherDetailSheet(weather: weather),
      ),
    );
  }

  void _maybeDismiss(BuildContext context, double? velocity) {
    if (velocity != null && velocity > 240) {
      Navigator.of(context).pop();
    }
  }
}

class _WeatherDetailSheet extends ConsumerWidget {
  const _WeatherDetailSheet({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.91;
    final location =
        weather.locationName.isNotEmpty
            ? weather.locationName
            : l10n.weatherSheetLocalFallback;
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    return Container(
      width: isWide ? 600 : double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.env.sheetSolid,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: context.env.line15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 60,
            offset: Offset(0, -25),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Stack(
          children: [
            const _WeatherSceneBackdrop(),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 19, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n
                                  .weatherSheetLocationEyebrow(location)
                                  .toUpperCase(),
                              style: TextStyle(
                                color: context.env.white70,
                                // ignore: font_size_whitelist
                                fontSize: 8,
                                letterSpacing: 1.4,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              weather.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.env.ink,
                                fontFamily: 'InstrumentSerif',
                                // ignore: font_size_whitelist
                                fontSize: 27,
                                height: 1.05,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip:
                            MaterialLocalizations.of(
                              context,
                            ).closeButtonTooltip,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: OmniIcon(
                          icon: OmniIcons.close,
                          size: 20,
                          color: context.env.ink,
                        ),
                        style: IconButton.styleFrom(
                          foregroundColor: context.env.ink,
                          minimumSize: const Size.square(48),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _WeatherCurrent(weather: weather),
                        if (weather.hourly.isNotEmpty)
                          _HourlyWeather(weather: weather),
                        _WeatherMetrics(weather: weather),
                        if (weather.daily.isNotEmpty)
                          _WeatherForecast(weather: weather),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: context.env.accent,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: context.env.accent,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.weatherSheetEnvironmentNote,
                                // ignore: font_size_whitelist
                                style: TextStyle(
                                  color: context.env.inkMuted,
                                  // ignore: font_size_whitelist
                                  fontSize: 8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 场景图头：壁纸 → 视频缩略图 → 打包默认壁纸三级兜底，恒有图。
class _WeatherSceneBackdrop extends ConsumerWidget {
  const _WeatherSceneBackdrop();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset =
        ref.watch(appBackdropControllerProvider).asData?.value.selectedBackdrop;
    final sceneUrl =
        asset?.isVideo == true
            ? (asset?.thumbnailPath?.isNotEmpty == true
                ? asset!.thumbnailPath
                : null)
            : asset?.path;
    return SizedBox(
      height: 250,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (sceneUrl != null && sceneUrl.isNotEmpty)
            Opacity(
              // 样例 weather-scene：saturate(.7) + opacity(.72)。
              opacity: 0.72,
              child: ColorFiltered(
                colorFilter: ColorFilter.matrix(<double>[
                  0.764,
                  0.215,
                  0.022,
                  0.000,
                  0.000,
                  0.064,
                  0.914,
                  0.022,
                  0.000,
                  0.000,
                  0.064,
                  0.215,
                  0.722,
                  0.000,
                  0.000,
                  0.000,
                  0.000,
                  0.000,
                  1.000,
                  0.000,
                ]),
                child: Image.network(
                  sceneUrl,
                  fit: BoxFit.cover,
                  errorBuilder:
                      (_, _, _) => Image.asset(
                        bundledWallpaperAssetPathFor(
                          AppBackdropSelectionTarget.mobile,
                        ),
                        fit: BoxFit.cover,
                      ),
                ),
              ),
            )
          else
            Image.asset(
              bundledWallpaperAssetPathFor(AppBackdropSelectionTarget.mobile),
              fit: BoxFit.cover,
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x0D080F0E), Color(0xFF17201E)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeatherCurrent extends StatelessWidget {
  const _WeatherCurrent({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OmniIcon(
                icon: OmniIcons.weatherFor(int.tryParse(weather.icon) ?? -1),
                size: 35,
                color: context.env.ink,
              ),
              const SizedBox(width: 14),
              // 样例 weather-current strong：固定 74px 衬线，不随宽度缩放。
              Text(
                '${weather.temp}°',
                style: TextStyle(
                  color: context.env.ink,
                  fontFamily: 'InstrumentSerif',
                  // ignore: font_size_whitelist
                  fontSize: 74,
                  height: 0.9,
                  letterSpacing: -3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.weatherSheetFeelsLike(weather.feelsLike),
            // ignore: font_size_whitelist
            style: TextStyle(
              color: context.env.ink,
              // ignore: font_size_whitelist
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            l10n.weatherSheetSummary,
            // ignore: font_size_whitelist
            style: TextStyle(color: context.env.inkMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _HourlyWeather extends StatelessWidget {
  const _HourlyWeather({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 样例固定 5 项、flex:1 均分（min-width 67），无横向间隙。
    final hours = weather.hourly.take(5).toList();
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: context.env.line13),
          bottom: BorderSide(color: context.env.line13),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      child: Row(
        children: [
          for (var index = 0; index < hours.length; index++) ...[
            if (index > 0) const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    index == 0 ? l10n.weatherHourNow : hours[index].displayTime,
                    // ignore: font_size_whitelist
                    style: TextStyle(
                      color: context.env.inkMuted,
                      // ignore: font_size_whitelist
                      fontSize: 8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OmniIcon(
                    icon: OmniIcons.weatherByCode(hours[index].icon),
                    size: 19,
                    color: context.env.ink,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${hours[index].temp}°',
                    style: TextStyle(
                      color: context.env.ink,
                      // ignore: font_size_whitelist
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeatherMetrics extends StatelessWidget {
  const _WeatherMetrics({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cells = <(String, String, String, bool)>[
      (
        l10n.weatherMetricWind,
        '${weather.windSpeed} km/h',
        weather.windDir,
        false,
      ),
      (l10n.weatherMetricHumidity, '${weather.humidity}%', '', false),
      (
        l10n.weatherMetricAirQuality,
        '${weather.aqi}',
        weather.aqiCategory,
        true,
      ),
      (l10n.weatherMetricSunset, weather.sunset, _sunsetDelta(context), false),
    ];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        border: Border.all(color: context.env.line13),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            for (var row = 0; row < 2; row++)
              IntrinsicHeight(
                child: Row(
                  children: [
                    for (var col = 0; col < 2; col++)
                      Expanded(
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 88),
                          decoration: BoxDecoration(
                            color: context.env.sheetSolid.withValues(
                              alpha: 0.95,
                            ),
                            border: Border(
                              right:
                                  col == 0
                                      ? BorderSide(color: context.env.line13)
                                      : BorderSide.none,
                              bottom:
                                  row == 0
                                      ? BorderSide(color: context.env.line13)
                                      : BorderSide.none,
                            ),
                          ),
                          padding: const EdgeInsets.all(14),
                          child: _MetricCell(
                            label: cells[row * 2 + col].$1,
                            value: cells[row * 2 + col].$2,
                            detail: cells[row * 2 + col].$3,
                            highlight: cells[row * 2 + col].$4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _sunsetDelta(BuildContext context) {
    final parsed = DateTime.tryParse(
      '${DateTime.now().toString().substring(0, 10)}T${weather.sunset}',
    );
    if (parsed == null) {
      return '';
    }
    final delta = parsed.difference(DateTime.now());
    if (delta.isNegative || delta.inMinutes < 1) {
      return '';
    }
    return AppLocalizations.of(context).weatherSunsetIn(delta.inMinutes);
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.label,
    required this.value,
    required this.detail,
    required this.highlight,
  });

  final String label;
  final String value;
  final String detail;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    // 样例 weather-metrics 单元格：标签置顶，数值紧随（margin 5 0 1），
    // 明细沉在数值下，全部顶部打包而非撑满沉底。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          // ignore: font_size_whitelist
          style: TextStyle(
            color: context.env.inkMuted,
            // ignore: font_size_whitelist
            fontSize: 7,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            color: context.env.ink,
            fontFamily: 'InstrumentSerif',
            // ignore: font_size_whitelist
            fontSize: 22,
            height: 1,
          ),
        ),
        const SizedBox(height: 1),
        if (detail.isNotEmpty)
          Text(
            detail,
            // ignore: font_size_whitelist
            style: TextStyle(
              color: highlight ? context.env.accent : context.env.inkMuted,
              // ignore: font_size_whitelist
              fontSize: 8,
            ),
          ),
      ],
    );
  }
}

class _WeatherForecast extends StatelessWidget {
  const _WeatherForecast({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final days = weather.daily.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 42,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.weatherForecastTitle.toUpperCase(),
                  // ignore: font_size_whitelist
                  style: TextStyle(
                    color: context.env.inkMuted,
                    // ignore: font_size_whitelist
                    fontSize: 8,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => unawaited(_openEnvironmentSettings(context)),
                icon: OmniIcon(
                  icon: OmniIcons.settings,
                  size: 14,
                  color: context.env.inkMuted,
                ),
                label: Text(l10n.weatherSettingsAction),
                style: TextButton.styleFrom(
                  foregroundColor: context.env.inkMuted,
                  minimumSize: const Size(48, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  // ignore: font_size_whitelist
                  textStyle: const TextStyle(fontSize: 8),
                ),
              ),
            ],
          ),
        ),
        for (var index = 0; index < days.length; index++)
          _ForecastRow(day: days[index], index: index),
      ],
    );
  }
}

class _ForecastRow extends StatelessWidget {
  const _ForecastRow({required this.day, required this.index});

  final WeatherDaily day;
  final int index;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final date = DateTime.tryParse(day.date);
    final label =
        index == 0
            ? l10n.weatherDayTomorrow
            : date == null
            ? day.date
            : DateFormat('EEEE').format(date);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x12FFFFFF))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: context.env.ink,
                // ignore: font_size_whitelist
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: Row(
              children: [
                OmniIcon(
                  icon: OmniIcons.weatherByCode(day.iconDay),
                  size: 18,
                  color: context.env.inkMuted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    day.textDay,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // ignore: font_size_whitelist
                    style: TextStyle(
                      color: context.env.inkMuted,
                      // ignore: font_size_whitelist
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              '${day.tempMax}°',
              style: TextStyle(
                color: context.env.ink,
                // ignore: font_size_whitelist
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 25,
            child: Text(
              '${day.tempMin}°',
              style: TextStyle(
                color: context.env.inkMuted,
                // ignore: font_size_whitelist
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 关闭天气面板后打开视觉环境面板（跨 async gap 用根导航上下文）。
Future<void> _openEnvironmentSettings(BuildContext sheetContext) async {
  final rootElement =
      sheetContext.findRootAncestorStateOfType<NavigatorState>();
  showAppBackdropSettings(sheetContext);
  rootElement?.pop();
}
