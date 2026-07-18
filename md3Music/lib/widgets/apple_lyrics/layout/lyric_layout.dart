import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Apple Music 风格歌词布局常量
///
/// 参照 spec.md "Requirement: 字号与行距" 与 "行为参数" / "alpha 参数" 章节，
/// 集中定义所有字号、行距、缩放、弹簧、滚动等布局常量与计算函数。
///
/// 本期目标平台为 Android，字号规则使用移动端 `max(8vw, 12px)`；
/// 桌面端规则 `max(max(5vh, 2.5vw), 12px)` 暂不实现。
class LyricLayout {
  LyricLayout._();

  // ============== 字号与行高（主行） ==============

  /// 字号（移动端）：`max(8vw, 12px)`
  ///
  /// Flutter 中通过 [MediaQuery] 取屏幕宽度乘 0.08，与 12 取 max。
  /// 1vw = 屏幕宽度 1%，故 8vw = width * 0.08。
  static double fontSize(BuildContext context) {
    final vw = MediaQuery.of(context).size.width * 0.08;
    return vw > 12 ? vw : 12;
  }

  /// 行高：1.2 倍
  static const double lineHeight = 1.2;

  // ============== 行 wrapper 间距 ==============

  /// 行 wrapper padding（垂直 0.4em，水平 1em）
  ///
  /// em 基于当前字号，需在调用处传入 [fontSize] 计算结果。
  static EdgeInsets linePadding(double fontSize) {
    return EdgeInsets.symmetric(
      vertical: fontSize * 0.4,
      horizontal: fontSize * 1.0,
    );
  }

  /// 行 wrapper 内 gap：0.3em
  static double lineGap(double fontSize) => fontSize * 0.3;

  // ============== 副行（翻译） ==============

  /// 副行（翻译）字号：`max(0.5em, 10px)`
  ///
  /// 0.5em 为主行字号的一半，再与 10px 取下限保护。
  static double translationFontSize(double fontSize) {
    final half = fontSize * 0.5;
    return half > 10 ? half : 10;
  }

  /// 副行行高：1.5em
  static const double translationLineHeight = 1.5;

  /// 副行透明度
  static const double translationOpacity = 0.3;

  // ============== 背景行（人声） ==============

  /// 背景行（人声）透明度
  static const double backgroundLineOpacity = 0.4;

  /// 背景行字号缩放
  static const double backgroundLineFontScale = 0.7;

  // ============== 行缩放 ==============

  /// 当前行缩放
  static const double activeScale = 1.0;

  /// 非当前行缩放（enableScale=true 时）
  static const double inactiveScale = 0.97;

  /// 背景行：当前行缩放
  static const double backgroundActiveScale = 1.0;

  /// 背景行：非当前行缩放
  static const double backgroundInactiveScale = 0.75;

  /// 缩放基准点：默认 left（对唱行 right）
  static const Alignment scaleOrigin = Alignment.centerLeft;

  /// 对唱行缩放基准点
  static const Alignment scaleOriginDuet = Alignment.centerRight;

  // ============== 颜色 ==============

  /// 文字颜色（固定白色 #FFFFFF）
  static const int textColorValue = 0xFFFFFFFF;

  /// 背景颜色（半透明黑 rgba(0,0,0,0.35)）
  ///
  /// 0.35 * 255 ≈ 89 = 0x59，故 ARGB 为 0x59000000。
  static const int backgroundColorValue = 0x59000000;

  // ============== alpha 参数 ==============

  /// 当前字已播亮态 alpha（满 scale 时 1.0）
  static const double currentBrightAlpha = 1.0;

  /// 当前字未播暗态 alpha（满 scale 时 0.2）
  static const double currentDarkAlpha = 0.2;

  /// ATTACK 速度：当前字变亮指数渐变系数
  static const double attackSpeed = 50.0;

  /// RELEASE 速度：当前字变暗指数渐变系数
  static const double releaseSpeed = 7.0;

  /// alpha 渐变阈值：低于此值认为已收敛
  static const double alphaEpsilon = 0.001;

  // ============== 滚动与对齐 ==============

  /// 对齐位置：行中心位于视口高度 35% 处（不是 0.5）
  static const double alignPosition = 0.35;

  /// overscan：视口上下额外预渲染像素
  static const double overscanPx = 300;

  /// 间奏阈值：相邻行间隔 >= 此值时渲染间奏点
  static const int interludeThresholdMs = 4000;

  /// 间奏提前结束：间奏动画提前此毫秒数结束以准备下一行
  static const int interludeEarlyEndMs = 250;

  /// 点击判定阈值：< 此像素值视为点击，否则视为滚动
  static const double clickThresholdPx = 10;

  /// 用户滚动后自动回弹到当前行的超时时间
  static const int autoReturnMs = 5000;

  // ============== 弹簧参数：行缩放 ==============

  /// 主行缩放弹簧：mass
  static const double scaleSpringMass = 2;

  /// 主行缩放弹簧：damping
  static const double scaleSpringDamping = 25;

  /// 主行缩放弹簧：stiffness
  static const double scaleSpringStiffness = 100;

  // ============== 弹簧参数：背景行缩放 ==============

  /// 背景行缩放弹簧：mass
  static const double bgScaleSpringMass = 1;

  /// 背景行缩放弹簧：damping
  static const double bgScaleSpringDamping = 20;

  /// 背景行缩放弹簧：stiffness
  static const double bgScaleSpringStiffness = 50;

  // ============== 弹簧参数：posY seeking/间奏模式 ==============

  /// posY seeking/间奏模式：stiffness
  static const double posYSeekingStiffness = 90;

  /// posY seeking/间奏模式：damping
  static const double posYSeekingDamping = 15;

  // ============== 弹簧参数：posY 普通播放动态范围 ==============

  /// posY 普通播放 stiffness 下限
  static const double posYNormalStiffnessMin = 170;

  /// posY 普通播放 stiffness 上限
  static const double posYNormalStiffnessMax = 220;

  /// posY 普通播放 interval 下限（ms）
  static const int posYNormalIntervalMinMs = 100;

  /// posY 普通播放 interval 上限（ms）
  static const int posYNormalIntervalMaxMs = 800;

  /// 计算 posY 普通播放的 stiffness
  ///
  /// 公式（spec.md "Scenario: posY 滚动弹簧（普通播放）"）：
  /// ```
  /// ratio = (1 - (interval - 100) / 700) ** 0.2
  /// stiffness = 170 + ratio * 50
  /// ```
  /// 其中 intervalMs 会被 clamp 到 [100, 800]：
  /// - interval=100ms（密集）→ ratio=1.0 → stiffness=220（最灵敏）
  /// - interval=800ms（稀疏）→ ratio=0.0 → stiffness=170（最迟缓）
  static double posYNormalStiffness(int intervalMs) {
    final clamped =
        intervalMs.clamp(posYNormalIntervalMinMs, posYNormalIntervalMaxMs)
            .toDouble();
    final ratio = math.pow(1 - (clamped - 100) / 700, 0.2).toDouble();
    return 170 + ratio * 50;
  }

  /// 计算 posY 普通播放的 damping
  ///
  /// 公式：`damping = sqrt(stiffness) * 2.2`
  ///
  /// 例：stiffness=220 → damping≈32.63；stiffness=170 → damping≈28.68。
  static double posYNormalDamping(double stiffness) {
    return math.sqrt(stiffness) * 2.2;
  }
}
