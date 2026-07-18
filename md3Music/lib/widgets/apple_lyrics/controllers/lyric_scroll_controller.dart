import 'package:flutter/widgets.dart';
import 'package:md3music/widgets/apple_lyrics/animation/spring.dart';
import 'package:md3music/widgets/apple_lyrics/layout/lyric_layout.dart';

/// 歌词滚动控制器
///
/// 参照 spec.md "Requirement: 弹簧物理动画引擎" 与 tasks.md Task 11 实现。
/// 用 [Spring] 驱动 `posY`（垂直滚动偏移），使当前行的中心始终位于
/// 视口高度 [LyricLayout.alignPosition]=0.35 处（不是 0.5）。
///
/// 设计要点：
/// - `tick(dt)` 由外部驱动（外部 Widget 用 `AnimationController` + `addListener`
///   调用 `tick`），因此构造函数不需要 `vsync` 参数。
/// - 普通播放模式下，弹簧参数由相邻行间隔动态决定（间隔越短，弹簧越灵敏）。
/// - seeking/间奏模式下使用固定参数（stiffness=90, damping=15），更稳定。
/// - 用户手动滚动后 5000ms 自动回弹到当前行。
class LyricScrollController {
  LyricScrollController() {
    _posYSpring = Spring(
      mass: 1,
      stiffness: LyricLayout.posYSeekingStiffness,
      damping: LyricLayout.posYSeekingDamping,
      initialPosition: 0,
    );
  }

  /// posY 弹簧
  late final Spring _posYSpring;

  /// 视口高度（像素）
  double _viewportHeight = 0;

  /// 当前行索引，-1 表示未设置
  int _currentLineIndex = -1;

  /// 当前行高度（用于自动回弹时计算 targetY）
  double _currentLineHeight = 0;

  /// 是否处于 seeking/间奏模式
  bool _isSeeking = false;

  /// 用户是否正在拖动
  bool _isUserScrolling = false;

  /// 自动回弹剩余倒计时（毫秒），<=0 且 _autoReturned=false 时表示等待回弹
  double _autoReturnRemainingMs = 0;

  /// 是否已自动回弹（避免在倒计时结束后重复 setTarget）
  bool _autoReturned = true;

  /// 当前弹簧 stiffness（用于测试与外部诊断）
  double _currentStiffness = LyricLayout.posYSeekingStiffness;

  /// 当前弹簧 damping（用于测试与外部诊断）
  double _currentDamping = LyricLayout.posYSeekingDamping;

  /// 视口高度
  double get viewportHeight => _viewportHeight;

  /// 当前行索引
  int get currentLineIndex => _currentLineIndex;

  /// 当前 posY（用于绘制时偏移）
  double get posY => _posYSpring.position;

  /// 当前弹簧目标（用于测试与外部诊断）
  double get currentTarget => _posYSpring.target;

  /// 当前弹簧 stiffness（用于测试）
  double get currentStiffness => _currentStiffness;

  /// 当前弹簧 damping（用于测试）
  double get currentDamping => _currentDamping;

  /// 设置视口尺寸
  void setViewportSize(Size size) {
    _viewportHeight = size.height;
  }

  /// 设置当前行
  ///
  /// [isSeeking] 为 true 时使用固定弹簧参数（stiffness=90, damping=15）；
  /// 为 false 时使用动态参数（基于 [intervalMs]）。
  ///
  /// [intervalMs] 为下一行 startTime - 当前行 endTime，仅 [isSeeking]=false
  /// 时用于计算动态 stiffness。会被 clamp 到 [100, 800]。
  ///
  /// [lineHeight] 为当前行的总高度（含 padding），用于计算 targetY。
  void setCurrentLine(
    int index, {
    required bool isSeeking,
    required double lineHeight,
    int intervalMs = 0,
  }) {
    _currentLineIndex = index;
    _currentLineHeight = lineHeight;
    _isSeeking = isSeeking;
    _applySpringParams(isSeeking, intervalMs);
    final double targetY = targetYForLine(index, lineHeight);
    _posYSpring.setTarget(targetY);
    // 切换到新行时，标记已对齐，不需要自动回弹
    _autoReturned = true;
    _autoReturnRemainingMs = 0;
  }

  /// 应用弹簧参数
  ///
  /// seeking/间奏模式：固定 stiffness=90, damping=15。
  /// 普通模式：stiffness = LyricLayout.posYNormalStiffness(intervalMs)，
  /// damping = LyricLayout.posYNormalDamping(stiffness)。
  void _applySpringParams(bool isSeeking, int intervalMs) {
    if (isSeeking) {
      _currentStiffness = LyricLayout.posYSeekingStiffness;
      _currentDamping = LyricLayout.posYSeekingDamping;
    } else {
      _currentStiffness = LyricLayout.posYNormalStiffness(intervalMs);
      _currentDamping = LyricLayout.posYNormalDamping(_currentStiffness);
    }
    _posYSpring.setParams(
      mass: 1,
      stiffness: _currentStiffness,
      damping: _currentDamping,
    );
  }

  /// 计算某行的目标 posY
  ///
  /// 公式：`targetY = -(lineTop + lineHeight/2 - viewportHeight * alignPosition)`
  ///
  /// 其中 `lineTop = lineIndex * lineHeight`（线性布局假设）。
  /// 负号因为滚动是反向偏移（posY 越负，内容越往上）。
  ///
  /// 例：viewport=600, lineHeight=40, lineIndex=0, alignPosition=0.35
  ///   → targetY = -(0 + 20 - 210) = 190
  double targetYForLine(int lineIndex, double lineHeight) {
    final double lineTop = lineIndex * lineHeight;
    return -(lineTop + lineHeight / 2 - _viewportHeight * LyricLayout.alignPosition);
  }

  /// 用户手动滚动（拖动）
  ///
  /// 直接修改 spring 的 position（不通过 setTarget），并重置 5000ms 倒计时。
  /// 在倒计时结束前若用户停止滚动，将自动回弹到当前行的 targetY。
  void onUserScroll(double delta) {
    // setPosition 会把 target 同步设为当前 position，弹簧暂时不会回弹；
    // 等 5000ms 倒计时结束后再 setTarget 触发回弹。
    _posYSpring.setPosition(_posYSpring.position + delta, 0);
    _isUserScrolling = true;
    _autoReturnRemainingMs = LyricLayout.autoReturnMs.toDouble();
    _autoReturned = false;
  }

  /// 用户滚动结束
  ///
  /// 从此时起开始 5000ms 倒计时，到时自动回弹到当前行。
  void onUserScrollEnd() {
    _isUserScrolling = false;
    // 仅在尚未回弹时重置倒计时
    if (!_autoReturned) {
      _autoReturnRemainingMs = LyricLayout.autoReturnMs.toDouble();
    }
  }

  /// 推进动画，返回是否需要重绘
  ///
  /// 返回 true 表示 spring 仍在运动或即将开始运动，需要重绘；false 表示已稳定。
  /// 同时负责推进自动回弹倒计时（用户停止滚动后 5000ms）。
  bool tick(double dt) {
    // 推进自动回弹倒计时（仅在用户停止滚动且尚未回弹时）
    if (!_isUserScrolling && !_autoReturned && _autoReturnRemainingMs > 0) {
      _autoReturnRemainingMs -= dt * 1000;
      if (_autoReturnRemainingMs <= 0) {
        _autoReturnRemainingMs = 0;
        _returnToCurrentLine();
      }
    }

    _posYSpring.tick(dt);
    return !_posYSpring.isSettled;
  }

  /// 自动回弹到当前行的 targetY
  void _returnToCurrentLine() {
    _autoReturned = true;
    if (_currentLineIndex < 0 || _currentLineHeight <= 0) return;
    final double targetY = targetYForLine(_currentLineIndex, _currentLineHeight);
    _posYSpring.setTarget(targetY);
  }

  /// 判断手势是否为点击
  ///
  /// 移动总距离 < [LyricLayout.clickThresholdPx]=10px 视为点击。
  bool isClickGesture(double totalDelta) {
    return totalDelta.abs() < LyricLayout.clickThresholdPx;
  }

  /// 设置普通/seeking 模式
  ///
  /// 切换模式时会立即应用对应的弹簧参数。
  /// [isSeeking]=true 使用固定参数（90, 15）；
  /// false 使用普通模式默认参数（intervalMs=0 → clamp 到 100，stiffness=220）。
  void setSeekingMode(bool isSeeking) {
    _isSeeking = isSeeking;
    _applySpringParams(isSeeking, 0);
  }

  /// 释放资源
  ///
  /// Spring 是纯 Dart 对象，无需显式释放，但保留 dispose 以便未来扩展
  /// （如内部添加 Ticker/AnimationController 时在此释放）。
  void dispose() {
    _currentLineIndex = -1;
    _viewportHeight = 0;
    _currentLineHeight = 0;
    _autoReturned = true;
    _autoReturnRemainingMs = 0;
  }
}
