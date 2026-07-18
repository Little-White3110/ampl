/// 整行降级渲染器（用于 LRC 与纯文本，无逐字时间戳）
///
/// 参照 spec.md "Requirement: 逐字 mask alpha 渲染" 中"非当前行渲染"场景与
/// tasks.md Task 10 实现。当 [LyricLine.hasWordTiming] 为 false 时启用整行模式：
/// - 当前行（isActive）：整行 alpha = 1.0（高亮）
/// - 非当前行：整行 alpha = 0.2（SOLID 模式，全行均匀暗）
/// - 行内无 mask 渐变，整行使用同一 alpha
/// - 行切换通过指数衰减实现淡入淡出过渡（变亮 ATTACK_SPEED=50，变暗 RELEASE_SPEED=7）
///
/// 与 [WordRenderer] 的关系：
/// - [WordRenderer] 处理 hasWordTiming=true 的逐字模式（有 mask 渐变）
/// - 本类处理 hasWordTiming=false 的整行模式（无 mask 渐变）
/// - 上层 AppleLyricsView 根据 hasWordTiming 调度使用哪个 renderer
///
/// 本类不是 Widget，是核心绘制逻辑类，由外部 CustomPainter 调用 [paintLine]。
/// 动画驱动由外部 AnimationController + Ticker 调用 [tick] 实现。
library;

import 'dart:math';

import 'package:flutter/widgets.dart';

import '../layout/lyric_layout.dart';
import '../models/lyric_line.dart';

/// 整行降级渲染器。
///
/// 持有当前 isActive 状态与单一 [_currentAlpha] 值（整行共用一个 alpha），
/// 通过 [tick] 推进指数衰减动画，通过 [paintLine] 用当前 alpha 绘制白色文本。
class LineRenderer {
  LineRenderer();

  // ============== 内部状态 ==============

  /// 当前是否为当前行（高亮）。默认 false（SOLID 暗态）。
  bool _isActive = false;

  /// 当前整行 alpha 值。初始 [LyricLayout.currentDarkAlpha]=0.2（SOLID 非当前行暗态）。
  double _currentAlpha = LyricLayout.currentDarkAlpha;

  /// 目标 alpha 值。isActive=true 时 1.0，false 时 0.2。
  double _targetAlpha = LyricLayout.currentDarkAlpha;

  // ============== 状态查询 ==============

  /// 当前 alpha（用于测试与外部协调）。
  double get currentAlpha => _currentAlpha;

  /// 当前是否为当前行。
  bool get isActive => _isActive;

  /// 目标 alpha（用于测试断言）。
  @visibleForTesting
  double get targetAlpha => _targetAlpha;

  // ============== 状态设置 ==============

  /// 设置当前行状态。
  ///
  /// [isActive] 为 true 时整行高亮（alpha 目标 1.0），
  /// 为 false 时整行 SOLID 暗态（alpha 目标 0.2）。
  /// [scale] 参数为保持与 [WordRenderer] API 一致而保留，
  /// 整行模式不做缩放，alpha 计算不受 scale 影响。
  void setLineState({required bool isActive, required double scale}) {
    _isActive = isActive;
    _targetAlpha =
        isActive ? LyricLayout.currentBrightAlpha : LyricLayout.currentDarkAlpha;
  }

  // ============== 动画推进 ==============

  /// 推进动画。
  ///
  /// [dt] 距上一帧的时间间隔（秒）。
  /// 用指数衰减公式 `_currentAlpha += (_targetAlpha - _currentAlpha) * (1 - exp(-speed * dt))`
  /// 平滑过渡：变亮用 [LyricLayout.attackSpeed]（50.0），变暗用 [LyricLayout.releaseSpeed]（7.0）。
  /// 差值小于 [LyricLayout.alphaEpsilon]（0.001）时吸附到目标。
  void tick(double dt) {
    if (dt <= 0) return;
    // 变亮用 ATTACK（快），变暗用 RELEASE（慢）
    final double speed = _targetAlpha >= _currentAlpha
        ? LyricLayout.attackSpeed
        : LyricLayout.releaseSpeed;
    final double decay = 1.0 - exp(-speed * dt);
    double next = _currentAlpha + (_targetAlpha - _currentAlpha) * decay;
    // 阈值收敛：差值小于 alphaEpsilon 直接吸附到目标
    if ((next - _targetAlpha).abs() < LyricLayout.alphaEpsilon) {
      next = _targetAlpha;
    }
    _currentAlpha = next;
  }

  // ============== 绘制 ==============

  /// 绘制整行歌词。
  ///
  /// [offset] 是行起始绘制原点。文字颜色固定白色 #FFFFFFFF，
  /// alpha 由 [_currentAlpha] 控制（整行同一 alpha，无 mask 渐变）。
  /// 使用 [TextPainter] 测量整行宽度并绘制。
  void paintLine(
      Canvas canvas, Offset offset, LyricLine line, double fontSize) {
    if (line.text.isEmpty) return;
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: line.text,
        style: TextStyle(
          // 文字颜色固定白色，alpha 整行统一（无 mask 渐变）
          color: Color.fromRGBO(255, 255, 255, _currentAlpha),
          fontSize: fontSize,
          height: LyricLayout.lineHeight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  /// 重置状态：alpha 回到初始值（0.2），isActive=false。
  void reset() {
    _isActive = false;
    _currentAlpha = LyricLayout.currentDarkAlpha;
    _targetAlpha = LyricLayout.currentDarkAlpha;
  }
}
