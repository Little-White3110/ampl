library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../layout/lyric_layout.dart';

/// 间奏点动画组件（AMLL 规范重做版）。
///
/// 新需求（grilling 第二轮确定）：
/// - **占位行**：间奏点作为一行内容嵌在歌词流里，行高 = 正常歌词行高，
///   随歌词滚动移动，而非悬浮在屏幕中央。
/// - **出现时机**：间奏开始前 [advanceShowMs]（3000ms）提前出现，
///   给用户预告。
/// - **动画曲线**：
///   1. 出现阶段（间奏开始瞬间）：3 个点 scale 从 1.0 放大到 1.2，
///      时长 [enlargeMs]（200ms）。
///   2. 消失阶段（间奏结束后）：3 个点 scale 从 1.2 缩小到 0，
///      时长 [shrinkMs]（400ms），缩小完成后占位行塌缩（歌词流收紧）。
/// - **AMLL 规范**：3 个白色小圆点居中横排。
/// - **未播放隐藏**：间奏开始前 3000ms 之外的时段完全不显示。
///
/// 调用方流程：
/// 1. 检测到间奏时段，调用 [setInterlude] 设置起止时间。
/// 2. 每帧调用 [tick] 推进时间。
/// 3. paint 时调用 [paintAtLineY] 在指定 y 坐标绘制（y = 占位行的 top）。
class InterludeDots {
  InterludeDots();

  // ============== 时长参数（ms）==============

  /// 间奏开始前提前显示的时间（ms）。
  static const int advanceShowMs = 3000;

  /// 出现阶段动画时长（ms）：1.0 → 1.2 放大。
  static const int enlargeMs = 200;

  /// 消失阶段动画时长（ms）：1.2 → 0 缩小消失。
  static const int shrinkMs = 400;

  /// 间奏阈值：相邻行间隔 >= 此值才显示间奏点。
  /// 取自 [LyricLayout.interludeThresholdMs]。
  static const int thresholdMs = LyricLayout.interludeThresholdMs;

  // ============== 状态 ==============

  /// 间奏起始时间（上一行 endTime）。
  int? _startTime;

  /// 间奏结束时间（下一行 startTime - interludeEarlyEndMs）。
  int? _endTime;

  /// 最近一次 tick 时间。
  int? _lastTickTime;

  // ============== 阶段枚举 ==============

  /// 间奏点当前所处阶段。
  ///
  /// - [InterludePhase.hidden]：未到显示时间，不绘制。
  /// - [InterludePhase.enlarging]：间奏开始瞬间，1.0 → 1.2 放大中（200ms）。
  /// - [InterludePhase.visible]：间奏进行中，保持 1.2 scale。
  /// - [InterludePhase.shrinking]：间奏结束，1.2 → 0 缩小中（400ms）。
  /// - [InterludePhase.collapsed]：已塌缩，占位行高度归零，不绘制。
  InterludePhase _phase = InterludePhase.hidden;
  InterludePhase get phase => _phase;

  /// 阶段开始时间（ms），用于计算阶段内进度。
  int _phaseStartMs = 0;

  // ============== Getter ==============

  int? get startTime => _startTime;
  int? get endTime => _endTime;

  /// 占位行当前实际高度（用于塌缩动画）。
  ///
  /// - hidden / collapsed 阶段：返回 0（不占空间）。
  /// - enlarging / visible / shrinking 阶段：返回 [fullLineHeight]。
  ///   简化实现：不单独做塌缩高度动画，shrinking 结束后直接归零。
  ///   若需要平滑塌缩，可在 shrinking 阶段按进度插值高度。
  double fullLineHeight = 0;

  /// 当前是否需要绘制（占位行有内容）。
  ///
  /// preview 阶段显示静态 1.0 scale 点，也需要绘制。
  bool get shouldRender =>
      _phase == InterludePhase.preview ||
      _phase == InterludePhase.enlarging ||
      _phase == InterludePhase.visible ||
      _phase == InterludePhase.shrinking;

  // ============== 状态设置 ==============

  /// 设置当前间奏时段。
  ///
  /// - [startTime] 间奏开始时间（上一行 endTime）。
  /// - [endTime] 间奏结束时间（下一行 startTime 减去
  ///   [LyricLayout.interludeEarlyEndMs]，本类不再二次扣减）。
  void setInterlude(int startTime, int endTime) {
    _startTime = startTime;
    _endTime = endTime;
    _phase = InterludePhase.hidden;
    _phaseStartMs = 0;
  }

  /// 清除间奏。
  void clear() {
    _startTime = null;
    _endTime = null;
    _lastTickTime = null;
    _phase = InterludePhase.hidden;
    _phaseStartMs = 0;
  }

  // ============== 时间推进 ==============

  /// 推进时间，更新当前阶段。
  ///
  /// 阶段转换逻辑：
  /// - hidden → enlarging：当 `now >= startTime - advanceShowMs` 时进入。
  ///   （但 enlarging 只在 `now >= startTime` 后才开始播放 200ms 放大动画；
  ///   在 advanceShowMs ~ startTime 之间保持 visible 状态显示静态 1.0 scale。）
  ///   **修正**：简化为——advanceShowMs 期间显示 1.0 scale 静态点，
  ///   间奏开始瞬间（now >= startTime）开始 enlarging 放大 200ms。
  /// - enlarging → visible：enlarging 播放完 200ms。
  /// - visible → shrinking：当 `now >= endTime` 时进入。
  /// - shrinking → collapsed：shrinking 播放完 400ms。
  ///
  /// 返回当前应显示的点数（3 或 0）。
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
        // 提前 advanceShowMs 显示静态点（1.0 scale）
        if (currentTimeMs >= start - advanceShowMs) {
          _phase = InterludePhase.preview;
          _phaseStartMs = currentTimeMs;
        }
        break;
      case InterludePhase.preview:
        // 间奏开始 → 进入放大阶段
        if (currentTimeMs >= start) {
          _phase = InterludePhase.enlarging;
          _phaseStartMs = currentTimeMs;
        } else if (currentTimeMs < start - advanceShowMs) {
          // 用户回退播放，回到 hidden
          _phase = InterludePhase.hidden;
        }
        break;
      case InterludePhase.enlarging:
        // 放大 200ms 完成 → visible
        if (currentTimeMs >= _phaseStartMs + enlargeMs) {
          _phase = InterludePhase.visible;
        }
        // 用户回退到间奏开始前 → 回到 preview
        if (currentTimeMs < start) {
          _phase = InterludePhase.preview;
          _phaseStartMs = currentTimeMs;
        }
        break;
      case InterludePhase.visible:
        // 间奏结束 → 进入缩小阶段
        if (currentTimeMs >= end) {
          _phase = InterludePhase.shrinking;
          _phaseStartMs = currentTimeMs;
        }
        // 用户回退到间奏开始前 → 回到 preview
        if (currentTimeMs < start) {
          _phase = InterludePhase.preview;
          _phaseStartMs = currentTimeMs;
        }
        break;
      case InterludePhase.shrinking:
        // 缩小 400ms 完成 → collapsed
        if (currentTimeMs >= _phaseStartMs + shrinkMs) {
          _phase = InterludePhase.collapsed;
        }
        // 用户回退到间奏内 → 回到 visible
        if (currentTimeMs < end && currentTimeMs >= start) {
          _phase = InterludePhase.visible;
        }
        break;
      case InterludePhase.collapsed:
        // 塌缩后不再显示，除非用户回退
        if (currentTimeMs < end) {
          _phase = InterludePhase.visible;
        }
        break;
    }

    return shouldRender ? 3 : 0;
  }

  /// 判断某时刻是否处于间奏中（间奏开始到结束之间）。
  bool isInterlude(int currentTimeMs) {
    final start = _startTime;
    final end = _endTime;
    if (start == null || end == null) return false;
    return currentTimeMs >= start && currentTimeMs < end;
  }

  /// 计算当前 scale（0 ~ 1.2）。
  ///
  /// - preview：1.0（静态显示）
  /// - enlarging：1.0 → 1.2（200ms 线性）
  /// - visible：1.2
  /// - shrinking：1.2 → 0（400ms 线性）
  /// - hidden / collapsed：0
  @visibleForTesting
  double currentScale(int currentTimeMs) {
    switch (_phase) {
      case InterludePhase.hidden:
      case InterludePhase.collapsed:
        return 0;
      case InterludePhase.preview:
        return 1.0;
      case InterludePhase.enlarging:
        final progress =
            ((currentTimeMs - _phaseStartMs) / enlargeMs).clamp(0.0, 1.0);
        return 1.0 + 0.2 * progress;
      case InterludePhase.visible:
        return 1.2;
      case InterludePhase.shrinking:
        final progress =
            ((currentTimeMs - _phaseStartMs) / shrinkMs).clamp(0.0, 1.0);
        return 1.2 * (1 - progress);
    }
  }

  /// 绘制 3 个间奏点（AMLL 规范：白色小圆点居中横排）。
  ///
  /// - [centerY]：占位行的垂直中心 y 坐标（随歌词滚动）。
  /// - [centerX]：占位行水平中心 x 坐标（通常为视口宽度 / 2）。
  /// - [dotRadius]：单点基准半径（默认 4px）。
  /// - [spacing]：点间距（默认 16px）。
  void paintAtLineY(
    Canvas canvas,
    double centerX,
    double centerY, {
    double dotRadius = 4,
    double spacing = 16,
  }) {
    if (!shouldRender) return;
    final now = _lastTickTime ?? _startTime ?? 0;
    final scale = currentScale(now);
    if (scale <= 0) return;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color.fromRGBO(255, 255, 255, 1.0);

    final r = dotRadius * scale;
    for (var i = 0; i < 3; i++) {
      final dx = centerX + (i - 1) * spacing;
      final dy = centerY;
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  /// 兼容旧接口 [paint]：转发到 [paintAtLineY]。
  /// 旧调用方传 `Offset(centerX, centerY)` 作为 center。
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

/// 间奏点动画阶段。
enum InterludePhase {
  /// 未到显示时间。
  hidden,

  /// 提前显示阶段（间奏开始前 3000ms）：静态 1.0 scale。
  preview,

  /// 放大阶段（间奏开始瞬间，200ms）：1.0 → 1.2。
  enlarging,

  /// 可见阶段（间奏进行中）：保持 1.2 scale。
  visible,

  /// 缩小阶段（间奏结束后，400ms）：1.2 → 0。
  shrinking,

  /// 已塌缩，占位行高度归零。
  collapsed,
}
