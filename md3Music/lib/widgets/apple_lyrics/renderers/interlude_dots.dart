library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../layout/lyric_layout.dart';

/// 间奏点动画组件。
///
/// 参照 spec.md "Requirement: 间奏点动画" 与 AMLL 项目
/// `packages/core/src/lyric-player/dom/interlude-dots.ts` 实现。
///
/// 当相邻两行歌词间隔 >= [LyricLayout.interludeThresholdMs]（4000ms）时
/// 进入间奏，在屏幕中央渲染 3 个水平排列、按相位错开呼吸的点，
/// 提前 [LyricLayout.interludeEarlyEndMs]（250ms）结束动画以准备下一行。
///
/// 调用方应在检测到间奏时调用 [setInterlude]，传入的 [setInterlude.endTime]
/// **必须是** 下一行 `startTime - interludeEarlyEndMs`（即已减去 250ms）。
/// 本类不再二次扣减，以保证时段边界与 [isInterlude] / [tick] 语义一致。
///
/// 点动画设计（参照 AMLL interlude-dots.ts）：
/// - 3 个点水平排列，半径 [paint] 的 `dotRadius` 参数（默认 4px）。
/// - 间奏时段总长 = `endTime - startTime`，3 个点各占 1/3 时段作为
///   "中心活跃期"。
/// - 点 i (i=0,1,2) 的活跃时刻 = `startTime + (endTime - startTime) * (i + 0.5) / 3`，
///   即归一化位置 1/6、1/2、5/6。
/// - 用 `sin(progress * pi)` 计算每个点的亮度与缩放：
///   `progress` 为当前时间在点 i 的活跃窗口 `[i/3, (i+1)/3]` 内的归一化进度
///   （0~1），窗口外 intensity=0（仍以最小 alpha=0.2 显示）。
/// - alpha 范围 0.2（最暗）~ 1.0（最亮）；scale 范围 0.5 ~ 1.5。
class InterludeDots {
  InterludeDots();

  /// 间奏起始时间（毫秒，上一行 endTime）。
  int? _startTime;

  /// 间奏结束时间（毫秒，已减去 [LyricLayout.interludeEarlyEndMs] 的下一行 startTime）。
  int? _endTime;

  /// 最近一次 [tick] 调用传入的时间，供 [paint] 在无显式时间参数时取用。
  int? _lastTickTime;

  /// 当前间奏起始时间。未设置时间奏时返回 null。
  int? get startTime => _startTime;

  /// 当前间奏结束时间。未设置时间奏时返回 null。
  int? get endTime => _endTime;

  /// 设置当前间奏时段。
  ///
  /// - [startTime] 间奏开始时间（上一行 endTime）。
  /// - [endTime] 间奏结束时间（下一行 startTime 减去
  ///   [LyricLayout.interludeEarlyEndMs]，本类不再二次扣减）。
  void setInterlude(int startTime, int endTime) {
    _startTime = startTime;
    _endTime = endTime;
    // 重置最近 tick 时间，避免上一段间奏的残留值污染新时段绘制
    _lastTickTime = null;
  }

  /// 清除间奏，恢复无间奏状态。
  void clear() {
    _startTime = null;
    _endTime = null;
    _lastTickTime = null;
  }

  /// 判断某时刻是否处于间奏中。
  ///
  /// 边界语义：`startTime <= t < endTime` 为间奏，
  /// 即 [setInterlude.startTime] 处包含、[setInterlude.endTime] 处不包含。
  bool isInterlude(int currentTimeMs) {
    final start = _startTime;
    final end = _endTime;
    if (start == null || end == null) return false;
    return currentTimeMs >= start && currentTimeMs < end;
  }

  /// 推进动画，返回当前应显示的点数。
  ///
  /// 间奏内返回 3（3 个点全部绘制，亮度由 [paint] 内部按活跃时刻计算），
  /// 间奏外返回 0（不绘制）。
  ///
  /// 同时缓存 [currentTimeMs] 供 [paint] 取用，故调用方应在每帧 [tick] 后
  /// 立即调用 [paint] 以保证动画时间同步。
  int tick(int currentTimeMs) {
    _lastTickTime = currentTimeMs;
    return isInterlude(currentTimeMs) ? 3 : 0;
  }

  /// 计算点 i 在指定时刻的亮度强度（0~1）。
  ///
  /// 供 [paint] 内部使用，亦供单元测试验证活跃时刻分布。
  /// - 点 i 的活跃窗口（归一化）= `[i/3, (i+1)/3]`。
  /// - 窗口内：`intensity = sin(progress * pi)`，`progress` ∈ [0, 1]。
  /// - 窗口外：`intensity = 0`（仍以最小 alpha=0.2 显示，由 [paint] 映射）。
  ///
  /// 间奏外或 i 不在 [0,2] 范围内时返回 0。
  @visibleForTesting
  double dotIntensity(int i, int currentTimeMs) {
    if (i < 0 || i > 2) return 0;
    final start = _startTime;
    final end = _endTime;
    if (start == null || end == null) return 0;
    final duration = end - start;
    if (duration <= 0) return 0;

    // 归一化时间 t ∈ [0, 1]
    final t = (currentTimeMs - start) / duration;
    if (t.isNaN) return 0;

    final windowStart = i / 3;
    final windowEnd = (i + 1) / 3;
    // 窗口外 intensity=0（边界处 sin(0)=sin(pi)=0，与窗口外连续）
    if (t < windowStart || t > windowEnd) return 0;

    final progress = (t - windowStart) * 3; // 0~1
    return math.sin(progress * math.pi);
  }

  /// 绘制 3 个间奏点。
  ///
  /// - [center] 3 个点的水平中心。
  /// - [radius] 3 个点的分布半径：点 0 在 `center.dx - radius`，点 1 在
  ///   `center.dx`，点 2 在 `center.dx + radius`（沿 x 轴水平排列）。
  /// - [dotRadius] 单点基准半径（默认 4px）。实际半径随 intensity 在
  ///   `dotRadius * 0.5` ~ `dotRadius * 1.5` 之间缩放。
  ///
  /// alpha 由 intensity 映射到 0.2~1.0；scale 映射到 0.5~1.5。
  /// 绘制时间取最近一次 [tick] 缓存的时间；若未调用过 [tick]，
  /// 则使用 [setInterlude.startTime] 作为兜底（绘制静态初始帧）。
  void paint(
    Canvas canvas,
    Offset center,
    double radius,
    double dotRadius,
  ) {
    final start = _startTime;
    final end = _endTime;
    if (start == null || end == null) return;

    // 时间来源：优先用最近一次 tick 的时间；未 tick 过则用间奏起点。
    // 间奏外（tick 缓存的时间已超出 [start, end)）不绘制，调用方应在
    // tick 返回 0 时跳过 paint，这里作为防御性兜底。
    final now = _lastTickTime ?? start;
    if (!isInterlude(now)) return;

    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < 3; i++) {
      final intensity = dotIntensity(i, now);
      // alpha: 0.2 ~ 1.0
      final alpha = 0.2 + 0.8 * intensity;
      // scale: 0.5 ~ 1.5
      final scale = 0.5 + 1.0 * intensity;
      final r = dotRadius * scale;

      // 3 个点水平排列：点 0 在左、点 1 在中、点 2 在右
      final dx = center.dx + (i - 1) * radius;
      final dy = center.dy;

      paint.color = Color.fromRGBO(255, 255, 255, alpha.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }
}
