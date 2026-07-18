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

      test('间奏时段内 tick 返回 3', () {
        expect(dots.tick(1000), equals(3));
        expect(dots.tick(3000), equals(3));
        expect(dots.tick(6999), equals(3));
      });

      test('间奏边界：startTime 处 isInterlude=true，endTime 处 isInterlude=false', () {
        // 边界包含起点
        expect(dots.isInterlude(start), isTrue);
        // 边界不包含终点
        expect(dots.isInterlude(end), isFalse);
      });

      test('间奏边界：startTime 处 tick=3，endTime 处 tick=0', () {
        expect(dots.tick(start), equals(3));
        expect(dots.tick(end), equals(0));
      });

      test('提前结束：endTime-250ms 时 tick 仍返回 3，到 endTime 时返回 0', () {
        // endTime 已是减去 250ms 的值（7250-250=7000）。
        // 在 endTime-250ms（即原始下一行 startTime - 500ms）时仍在间奏内
        expect(dots.tick(end - LyricLayout.interludeEarlyEndMs), equals(3));
        // 到 endTime（已减 250ms）时返回 0
        expect(dots.tick(end), equals(0));
      });

      test('间奏外时刻 isInterlude 返回 false', () {
        expect(dots.isInterlude(start - 1), isFalse);
        expect(dots.isInterlude(end), isFalse);
        expect(dots.isInterlude(end + 1000), isFalse);
      });

      test('间奏外时刻 tick 返回 0', () {
        expect(dots.tick(start - 1), equals(0));
        expect(dots.tick(end), equals(0));
        expect(dots.tick(end + 1000), equals(0));
      });

      test('3 个点活跃时刻分布：点 0 在 1/6 处、点 1 在 1/2 处、点 2 在 5/6 处最亮', () {
        // 时段长度 6000ms
        // 点 0 活跃时刻 = start + 6000 * 1/6 = 1000 + 1000 = 2000
        // 点 1 活跃时刻 = start + 6000 * 1/2 = 1000 + 3000 = 4000
        // 点 2 活跃时刻 = start + 6000 * 5/6 = 1000 + 5000 = 6000
        const peak0 = start + (end - start) * 1 ~/ 6; // 2000
        const peak1 = start + (end - start) * 1 ~/ 2; // 4000
        const peak2 = start + (end - start) * 5 ~/ 6; // 6000
        expect(peak0, equals(2000));
        expect(peak1, equals(4000));
        expect(peak2, equals(6000));

        // 点 0 在 peak0 处最亮（intensity≈1.0），其他点更暗
        expect(dots.dotIntensity(0, peak0), closeTo(1.0, 1e-9));
        expect(dots.dotIntensity(1, peak0), lessThan(dots.dotIntensity(0, peak0)));
        expect(dots.dotIntensity(2, peak0), lessThan(dots.dotIntensity(0, peak0)));

        // 点 1 在 peak1 处最亮
        expect(dots.dotIntensity(1, peak1), closeTo(1.0, 1e-9));
        expect(dots.dotIntensity(0, peak1), lessThan(dots.dotIntensity(1, peak1)));
        expect(dots.dotIntensity(2, peak1), lessThan(dots.dotIntensity(1, peak1)));

        // 点 2 在 peak2 处最亮
        expect(dots.dotIntensity(2, peak2), closeTo(1.0, 1e-9));
        expect(dots.dotIntensity(0, peak2), lessThan(dots.dotIntensity(2, peak2)));
        expect(dots.dotIntensity(1, peak2), lessThan(dots.dotIntensity(2, peak2)));
      });

      test('点活跃窗口边界 intensity=0，与窗口外连续', () {
        // 点 0 活跃窗口 [0, 1/3]，即归一化 t∈[0, 1/3]
        // 窗口边界 progress=0 或 1 时 sin=0
        // 点 0 窗口左边界 = start，右边界 = start + (end-start)/3 = 1000 + 2000 = 3000
        expect(dots.dotIntensity(0, start), closeTo(0.0, 1e-9));
        expect(dots.dotIntensity(0, start + (end - start) ~/ 3), closeTo(0.0, 1e-9));
        // 窗口外（右）intensity=0，与边界连续
        expect(dots.dotIntensity(0, start + (end - start) ~/ 3 + 1), equals(0.0));
        // 窗口外（左）intensity=0
        expect(dots.dotIntensity(0, start - 1), equals(0.0));
      });

      test('intensity 范围 [0, 1]', () {
        // 在间奏期内多个时刻采样，确保 intensity 始终在 [0,1]
        for (var t = start; t < end; t += 100) {
          for (var i = 0; i < 3; i++) {
            final v = dots.dotIntensity(i, t);
            expect(v, greaterThanOrEqualTo(0.0));
            expect(v, lessThanOrEqualTo(1.0));
          }
        }
      });

      test('间奏外时刻 dotIntensity 返回 0', () {
        expect(dots.dotIntensity(0, start - 100), equals(0.0));
        expect(dots.dotIntensity(0, end + 100), equals(0.0));
        expect(dots.dotIntensity(1, start - 100), equals(0.0));
        expect(dots.dotIntensity(2, end + 100), equals(0.0));
      });

      test('i 越界时 dotIntensity 返回 0', () {
        expect(dots.dotIntensity(-1, 3000), equals(0.0));
        expect(dots.dotIntensity(3, 3000), equals(0.0));
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
        expect(dots.tick(3000), equals(3));

        dots.clear();
        expect(dots.tick(3000), equals(0));
        expect(dots.tick(1000), equals(0));
      });

      test('clear 后 dotIntensity 返回 0', () {
        final dots = InterludeDots();
        dots.setInterlude(1000, 7000);
        expect(dots.dotIntensity(1, 4000), closeTo(1.0, 1e-9));

        dots.clear();
        expect(dots.dotIntensity(0, 2000), equals(0.0));
        expect(dots.dotIntensity(1, 4000), equals(0.0));
        expect(dots.dotIntensity(2, 6000), equals(0.0));
      });
    });

    group('setInterlude 重新设置', () {
      test('重新设置后旧时段失效，新时段生效', () {
        final dots = InterludeDots();
        dots.setInterlude(1000, 7000);
        expect(dots.isInterlude(3000), isTrue);

        // 重新设置为新时段
        dots.setInterlude(10000, 20000);
        expect(dots.isInterlude(3000), isFalse); // 旧时段已失效
        expect(dots.isInterlude(15000), isTrue); // 新时段生效
        expect(dots.tick(15000), equals(3));
      });
    });

    group('间奏检测规则集成（参照 spec.md）', () {
      test('相邻行间隔 >= 4000ms 应触发间奏（由调用方判定，本类只接收时段）', () {
        // 模拟：当前行 endTime=1000，下一行 startTime=6000，间隔 5000ms >= 4000ms
        // 调用方应调用 setInterlude(1000, 6000 - 250) = setInterlude(1000, 5750)
        final dots = InterludeDots();
        const currentEnd = 1000;
        const nextStart = 6000;
        const gap = nextStart - currentEnd; // 5000ms
        expect(gap, greaterThanOrEqualTo(LyricLayout.interludeThresholdMs));

        dots.setInterlude(currentEnd, nextStart - LyricLayout.interludeEarlyEndMs);
        // 间奏期间
        expect(dots.isInterlude(currentEnd), isTrue);
        expect(dots.isInterlude(nextStart - LyricLayout.interludeEarlyEndMs - 1), isTrue);
        // 间奏结束（已提前 250ms）
        expect(dots.isInterlude(nextStart - LyricLayout.interludeEarlyEndMs), isFalse);
        // 间奏内 tick=3
        expect(dots.tick(currentEnd + 1000), equals(3));
      });

      test('相邻行间隔 < 4000ms 不应触发间奏（调用方不调用 setInterlude）', () {
        // 模拟：当前行 endTime=1000，下一行 startTime=4000，间隔 3000ms < 4000ms
        // 调用方应不调用 setInterlude，InterludeDots 保持初始状态
        final dots = InterludeDots();
        const currentEnd = 1000;
        const nextStart = 4000;
        const gap = nextStart - currentEnd; // 3000ms
        expect(gap, lessThan(LyricLayout.interludeThresholdMs));

        // 不调用 setInterlude
        expect(dots.isInterlude(currentEnd), isFalse);
        expect(dots.tick(currentEnd + 1000), equals(0));
      });
    });
  });
}
