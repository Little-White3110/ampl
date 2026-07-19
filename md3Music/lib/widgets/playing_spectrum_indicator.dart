import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 正在播放频谱标识。
///
/// 用 Ticker 驱动 3 根粒度柱高度做 sin 波动，周期 800ms，
/// 三根柱相位错开 0 / 0.4 / 0.8，呈现类似 Apple Music / 网易云的「正在播放」装饰性动画。
///
/// 仅是装饰性动画（不订阅 amplitudeStream / 不需要任何权限），
/// 用来替代 [CircularProgressIndicator] loading 圈作为歌曲列表「正在播放」标识。
class PlayingSpectrumIndicator extends StatefulWidget {
  final Color color;

  /// 整体尺寸（正方形），默认 14×14
  final double size;

  const PlayingSpectrumIndicator({
    super.key,
    required this.color,
    this.size = 14,
  });

  @override
  State<PlayingSpectrumIndicator> createState() =>
      _PlayingSpectrumIndicatorState();
}

class _PlayingSpectrumIndicatorState extends State<PlayingSpectrumIndicator>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    _t += dt;
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    // 3 根柱基础高度 + 振幅
    final baseHeight = size * 0.4;
    final ampHeight = size * 0.5;
    // 周期 800ms = 0.8s
    final period = 0.8;

    final barHeights = List<double>.generate(3, (i) {
      // 相位错开 0 / 0.4 / 0.8
      final phase = i * 0.4;
      final s = (math.sin((_t / period + phase) * 2 * math.pi) + 1) / 2;
      return baseHeight + ampHeight * s;
    });

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SpectrumPainter(
          color: widget.color,
          barHeights: barHeights,
          barWidth: size / 4.5,
          spacing: size / 6,
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  final Color color;
  final List<double> barHeights;
  final double barWidth;
  final double spacing;

  const _SpectrumPainter({
    required this.color,
    required this.barHeights,
    required this.barWidth,
    required this.spacing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final totalWidth = 3 * barWidth + 2 * spacing;
    final startX = (size.width - totalWidth) / 2;
    for (int i = 0; i < 3; i++) {
      final x = startX + i * (barWidth + spacing);
      final h = barHeights[i];
      final y = (size.height - h) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, h),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.barHeights != barHeights;
}
