import 'package:flutter_test/flutter_test.dart';
import 'package:md3music/widgets/apple_lyrics/layout/lyric_layout.dart';
import 'package:md3music/widgets/apple_lyrics/renderers/interlude_dots.dart';

void main() {
  group('InterludeDots', () {
    test('初始状态：无间奏，isInterlude 返回 false，tick 返回 0', () {
      final dots = InterludeDots();
      expect(dots.startTime, isNull);
      expect(dots.endTime, isNull);
      expect(dots.isInterlude(0), isFalse);
      expect(dots.isInterlude(5000), isFalse);
      expect(dots.tick(0), equals(0));
      expect(dots.tick(5000), equals(0));
    });

    group('设置间奏后 (start=1000, end=7000)', () {
      // 注意：按 API 约定，endTime 是调用方已减去 interludeEarlyEndMs(250ms) 的值。
      // 这里模拟"下一行 startTime=7250ms"的场景，传入 endTime=7250-250=7000。
      const start = 1000;
      const end = 7000;
      late InterludeDots dots;

      setUp(() {
        dots = InterludeDots();
        dots.setInterlude(start, end);
      });

      test('间奏时段内 isInterlude 返回 true', () {
        expect(dots.isInterlude(1000), isTrue);
        expect(dots.isInterlude(3000), isTrue);
        expect(dots.isInterlude(6999), isTrue);
      });

      test('间奏边界：startTime 处 isInterlude=true，endTime 处 isInterlude=false', () {
        expect(dots.isInterlude(start), isTrue);
        expect(dots.isInterlude(end), isFalse);
      });

      test('间奏外时刻 isInterlude 返回 false', () {
        expect(dots.isInterlude(start - 1), isFalse);
        expect(dots.isInterlude(end), isFalse);
        expect(dots.isInterlude(end + 1000), isFalse);
      });
    });

    group('clear()', () {
      test('clear 后 isInterlude 返回 false', () {
        final dots = InterludeDots();
        dots.setInterlude(1000, 7000);
        expect(dots.isInterlude(3000), isTrue);

        dots.clear();
        expect(dots.startTime, isNull);
        expect(dots.endTime, isNull);
        expect(dots.isInterlude(3000), isFalse);
        expect(dots.isInterlude(1000), isFalse);
      });

      test('clear 后 tick 返回 0', () {
        final dots = InterludeDots();
        dots.setInterlude(1000, 7000);
        dots.tick(3000); // 推进到间奏内

        dots.clear();
        expect(dots.tick(3000), equals(0));
        expect(dots.tick(1000), equals(0));
      });
    });

    group('setInterlude 重新设置', () {
      test('重新设置后旧时段失效，新时段生效', () {
        final dots = InterludeDots();
        dots.setInterlude(1000, 7000);
        expect(dots.isInterlude(3000), isTrue);

        dots.setInterlude(10000, 20000);
        expect(dots.isInterlude(3000), isFalse);
        expect(dots.isInterlude(15000), isTrue);
      });
    });

    group('新阶段状态机（AMLL 规范重做版）', () {
      test('间奏开始前 3000ms 进入 preview 阶段（shouldRender=true）', () {
        final dots = InterludeDots();
        dots.setInterlude(10000, 20000);
        // 7000ms 处（间奏前 3000ms）应进入 preview
        expect(dots.tick(7000), equals(3));
        expect(dots.phase, equals(InterludePhase.preview));
        expect(dots.shouldRender, isTrue);
      });

      test('间奏开始前 3001ms 仍为 hidden', () {
        final dots = InterludeDots();
        dots.setInterlude(10000, 20000);
        expect(dots.tick(6999), equals(0));
        expect(dots.phase, equals(InterludePhase.hidden));
        expect(dots.shouldRender, isFalse);
      });

      test('间奏开始瞬间进入 enlarging 阶段', () {
        final dots = InterludeDots();
        dots.setInterlude(10000, 20000);
        dots.tick(9000); // preview
        dots.tick(10000); // enlarging
        expect(dots.phase, equals(InterludePhase.enlarging));
        expect(dots.shouldRender, isTrue);
      });

      test('enlarging 200ms 后进入 visible', () {
        final dots = InterludeDots();
        dots.setInterlude(10000, 20000);
        dots.tick(10000); // enlarging start
        dots.tick(10200); // 200ms 后
        expect(dots.phase, equals(InterludePhase.visible));
      });

      test('间奏结束进入 shrinking', () {
        final dots = InterludeDots();
        dots.setInterlude(10000, 20000);
        dots.tick(10000); // enlarging
        dots.tick(10200); // visible
        dots.tick(20000); // shrinking
        expect(dots.phase, equals(InterludePhase.shrinking));
      });

      test('shrinking 400ms 后进入 collapsed', () {
        final dots = InterludeDots();
        dots.setInterlude(10000, 20000);
        dots.tick(10000);
        dots.tick(10200);
        dots.tick(20000); // shrinking
        dots.tick(20400); // 400ms 后
        expect(dots.phase, equals(InterludePhase.collapsed));
        expect(dots.shouldRender, isFalse);
      });

      test('currentScale：preview=1.0, visible=1.2, hidden=0', () {
        final dots = InterludeDots();
        dots.setInterlude(10000, 20000);
        dots.tick(7000); // preview
        expect(dots.currentScale(7000), equals(1.0));
        dots.tick(10200); // visible
        expect(dots.currentScale(10200), equals(1.2));
        dots.clear();
        expect(dots.currentScale(0), equals(0));
      });

      test('enlarging 阶段 scale 从 1.0 线性到 1.2', () {
        final dots = InterludeDots();
        dots.setInterlude(10000, 20000);
        dots.tick(10000); // enlarging start
        // 100ms 后应在 1.0 + 0.2 * 0.5 = 1.1
        final scale = dots.currentScale(10100);
        expect(scale, closeTo(1.1, 0.01));
      });

      test('shrinking 阶段 scale 从 1.2 线性到 0', () {
        final dots = InterludeDots();
        dots.setInterlude(10000, 20000);
        dots.tick(10000);
        dots.tick(10200);
        dots.tick(20000); // shrinking start
        // 200ms 后应在 1.2 * (1 - 0.5) = 0.6
        final scale = dots.currentScale(20200);
        expect(scale, closeTo(0.6, 0.01));
      });
    });

    group('间奏检测规则集成（参照 spec.md）', () {
      test('相邻行间隔 >= 4000ms 应触发间奏（由调用方判定，本类只接收时段）', () {
        final dots = InterludeDots();
        const currentEnd = 1000;
        const nextStart = 6000;
        const gap = nextStart - currentEnd;
        expect(gap, greaterThanOrEqualTo(LyricLayout.interludeThresholdMs));

        dots.setInterlude(currentEnd, nextStart - LyricLayout.interludeEarlyEndMs);
        expect(dots.isInterlude(currentEnd), isTrue);
        expect(dots.isInterlude(nextStart - LyricLayout.interludeEarlyEndMs - 1), isTrue);
        expect(dots.isInterlude(nextStart - LyricLayout.interludeEarlyEndMs), isFalse);
      });

      test('相邻行间隔 < 4000ms 不应触发间奏（调用方不调用 setInterlude）', () {
        final dots = InterludeDots();
        const currentEnd = 1000;
        const nextStart = 4000;
        const gap = nextStart - currentEnd;
        expect(gap, lessThan(LyricLayout.interludeThresholdMs));

        expect(dots.isInterlude(currentEnd), isFalse);
        expect(dots.tick(currentEnd + 1000), equals(0));
      });
    });
  });
}
