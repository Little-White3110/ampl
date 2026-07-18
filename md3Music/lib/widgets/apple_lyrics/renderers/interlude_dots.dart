library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../layout/lyric_layout.dart';

/// 间奏点动画组件（AMLL 规范重做版 v2）。
///
/// 新需求（grilling 第三轮确定）：
/// - **占位行 + 左对齐**：3 个点跟歌词一样左对齐到 [startX]，画在
///   当前行的下一行位置（N+1 行），视觉上嵌在歌词流里。
/// - **AMLL 循环呼吸**：3 个点按相位 0°/120°/240° 错开呼吸（亮度循环）。
///   - 每个点亮度 = 0.4 + 0.6 * (sin(phase + t * speed) * 0.5 + 0.5)
///   - t 为间奏内相对时间（ms），speed=2π/1500ms（1500ms 一个周期）
/// - **出现/消失动画**：
///   1. 提前 [advanceShowMs]（3000ms）显示，初始 scale=0，渐显到 1.0（fade-in 300ms）
///   2. 间奏开始瞬间不再单独放大（之前的 1.0→1.2 删除，跟 AMLL 循环呼吸冲突）
///   3. 间奏结束后 scale 从 1.0 → 0（shrink 400ms），随后占位行塌缩
/// - **未播放隐藏**：间奏开始前 3000ms 之外完全不显示。
///
/// 调用方流程：
/// 1. 检测到间奏时段，调用 [setInterlude] 设置起止时间。
/// 2. 每帧调用 [tick] 推进时间，返回当前应显示的点数（3 或 0）。
/// 3. paint 时调用 [paintAtLineY] 在指定 y 坐标绘制（y = 占位行的 top）。
class InterludeDots {
  InterludeDots();

  // ============== 时长参数（ms）==============

  /// 间奏开始前提前显示的时间（ms）。
  static const int advanceShowMs = 3000;

  /// fade-in 时长（ms）：提前显示后从 scale 0 → 1.0。
  static const int fadeInMs = 300;

  /// 消失阶段时长（ms）：间奏结束后 scale 1.0 → 0。
  static const int shrinkMs = 400;

  /// AMLL 循环呼吸周期（ms）：3 个点相位错开，每 [breathPeriodMs] 完成一次循环。
  static const int breathPeriodMs = 1500;

  /// 3 个点的相位错开角度（弧度）：0, 2π/3, 4π/3。
  static final List<double> dotPhases = [
    0.0,
    2 * math.pi / 3,
    4 * math.pi / 3,
  ];

  /// 间奏阈值：相邻行间隔 >= 此值才显示间奏点。
  /// 取自 [LyricLayout.interludeThresholdMs]。
  static const int thresholdMs = LyricLayout.interludeThresholdMs;

  // ============== 状态 ==============

  int? _startTime;
  int? _endTime;
  int? _lastTickTime;

  InterludePhase _phase = InterludePhase.hidden;
  InterludePhase get phase => _phase;

  int _phaseStartMs = 0;

  // ============== Getter ==============

  int? get startTime => _startTime;
  int? get endTime => _endTime;

  /// 当前是否需要绘制。
  bool get shouldRender =>
      _phase == InterludePhase.preview ||
      _phase == InterludePhase.visible ||
      _phase == InterludePhase.shrinking;

  // ============== 状态设置 ==============

  void setInterlude(int startTime, int endTime) {
    _startTime = startTime;
    _endTime = endTime;
    _phase = InterludePhase.hidden;
    _phaseStartMs = 0;
  }

  void clear() {
    _startTime = null;
    _endTime = null;
    _lastTickTime = null;
    _phase = InterludePhase.hidden;
    _phaseStartMs = 0;
  }

  // ============== 时间推进 ==============

  /// 推进时间，更新阶段，返回应显示点数（3 或 0）。
  ///
  /// 阶段转换：
  /// - hidden → preview：`now >= start - advanceShowMs`，开始 fade-in。
  /// - preview → visible：`now >= start`，进入循环呼吸。
  /// - visible → shrinking：`now >= end`，开始缩小消失。
  /// - shrinking → collapsed：shrink 播完 400ms。
  /// - 任何阶段支持 seek 回退恢复。
  int tick(int currentTimeMs) {
    _lastTickTime = currentTimeMs;
    final start = _startTime;
    final end = _endTime;
    if (start == null || end == null) {
      _phase = InterludePhase.hidden;
      return 0;
    }

    switch (_phase) {
      case InterludePhase.hidden:
        if (currentTimeMs >= start - advanceShowMs) {
          _phase = InterludePhase.preview;
          _phaseStartMs = currentTimeMs;
        }
        break;
      case InterludePhase.preview:
        if (currentTimeMs >= start) {
          _phase = InterludePhase.visible;
          _phaseStartMs = currentTimeMs;
        } else if (currentTimeMs < start - advanceShowMs) {
          _phase = InterludePhase.hidden;
        }
        break;
      case InterludePhase.visible:
        if (currentTimeMs >= end) {
          _phase = InterludePhase.shrinking;
          _phaseStartMs = currentTimeMs;
        } else if (currentTimeMs < start) {
          _phase = InterludePhase.preview;
          _phaseStartMs = currentTimeMs;
        }
        break;
      case InterludePhase.shrinking:
        if (currentTimeMs >= _phaseStartMs + shrinkMs) {
          _phase = InterludePhase.collapsed;
        }
        if (currentTimeMs < end) {
          _phase = InterludePhase.visible;
          _phaseStartMs = currentTimeMs;
        }
        break;
      case InterludePhase.collapsed:
        if (currentTimeMs < end) {
          _phase = InterludePhase.visible;
          _phaseStartMs = currentTimeMs;
        }
        break;
    }

    return shouldRender ? 3 : 0;
  }

  bool isInterlude(int currentTimeMs) {
    final start = _startTime;
    final end = _endTime;
    if (start == null || end == null) return false;
    return currentTimeMs >= start && currentTimeMs < end;
  }

  /// 计算整体 scale（0 ~ 1.0）。
  ///
  /// - preview 阶段：0 → 1.0 fade-in（300ms）
  /// - visible 阶段：1.0
  /// - shrinking 阶段：1.0 → 0（400ms）
  @visibleForTesting
  double currentScale(int currentTimeMs) {
    switch (_phase) {
      case InterludePhase.hidden:
      case InterludePhase.collapsed:
        return 0;
      case InterludePhase.preview:
        final progress =
            ((currentTimeMs - _phaseStartMs) / fadeInMs).clamp(0.0, 1.0);
        return progress;
      case InterludePhase.visible:
        return 1.0;
      case InterludePhase.shrinking:
        final progress =
            ((currentTimeMs - _phaseStartMs) / shrinkMs).clamp(0.0, 1.0);
        return 1.0 - progress;
    }
  }

  /// 计算指定点的当前亮度（0.4 ~ 1.0，AMLL 循环呼吸）。
  ///
  /// - 非可见阶段：返回 [baseAlpha]（0.4）
  /// - 可见阶段：`0.4 + 0.6 * (sin(phase + 2π * t / period) * 0.5 + 0.5)`
  ///   t = 间奏内相对时间（ms），period=1500ms
  @visibleForTesting
  double dotIntensity(int dotIndex, int currentTimeMs) {
    if (_phase != InterludePhase.visible) {
      return 0.4;
    }
    final start = _startTime ?? currentTimeMs;
    final t = (currentTimeMs - start).toDouble();
    final phase = dotPhases[dotIndex % 3];
    final omega = 2 * math.pi / breathPeriodMs;
    final wave = math.sin(phase + omega * t) * 0.5 + 0.5;
    return 0.4 + 0.6 * wave;
  }

  /// 绘制 3 个间奏点（AMLL 规范：白色小圆点左对齐横排）。
  ///
  /// - [startX]：左边距（与歌词文字 startX 一致）
  /// - [centerY]：占位行的垂直中心 y 坐标（随歌词滚动）
  /// - [dotRadius]：单点基准半径（默认 4px）
  /// - [spacing]：点间距（默认 16px）
  void paintAtLineY(
    Canvas canvas,
    double startX,
    double centerY, {
    double dotRadius = 4,
    double spacing = 16,
  }) {
    if (!shouldRender) return;
    final now = _lastTickTime ?? _startTime ?? 0;
    final scale = currentScale(now);
    if (scale <= 0) return;

    final r = dotRadius * scale;
    for (var i = 0; i < 3; i++) {
      final intensity = dotIntensity(i, now);
      final dx = startX + i * spacing + r;
      final dy = centerY;
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = Color.fromRGBO(255, 255, 255, intensity * scale);
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  /// 兼容旧接口 [paint]，转发到 [paintAtLineY]（center 作为左对齐起点）。
  void paint(
    Canvas canvas,
    Offset center,
    double radius,
    double dotRadius,
  ) {
    paintAtLineY(
      canvas,
      center.dx,
      center.dy,
      dotRadius: dotRadius,
      spacing: radius,
    );
  }
}

enum InterludePhase {
  hidden,
  preview,
  visible,
  shrinking,
  collapsed,
}
