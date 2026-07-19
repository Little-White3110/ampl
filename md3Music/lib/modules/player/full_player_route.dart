import 'package:flutter/material.dart';

import 'full_player.dart';

/// 从底部滑入的 [MaterialPageRoute] 子类。
///
/// 用于 FullPlayer 路由，支持预测性返回手势（Android 14+）：
///
/// **关键设计**：
/// 1. 继承 [MaterialPageRoute] → 保留与系统预测返回手势的对接
///    （系统知道如何驱动 animation 反向播放实现预测动画）
/// 2. 重写 [buildTransitions] → 用框架传入的 `animation` 驱动 [SlideTransition]
///    - push 时：animation 0→1，页面从 Offset(0,1) 滑到 Offset.zero（从底部滑入）
///    - 预测返回时：系统驱动 animation 1→0 反向播放，页面自然向下平移
/// 3. 不使用自定义 AnimationController，完全依赖框架的 animation
///
/// **与 [PageRouteBuilder] + transitionsBuilder 的区别**：
/// PageRouteBuilder 没有继承 _MaterialRouteTransitionMixin，缺少与系统手势的对接，
/// 自定义 transition 会禁用预测返回。本类继承 MaterialPageRoute 保留对接。
///
/// **作用域**：
/// 只作用于 FullPlayer 路由，不影响其他 MaterialPageRoute（如 /search /settings）。
class BottomSlideMaterialPageRoute<T> extends MaterialPageRoute<T> {
  BottomSlideMaterialPageRoute({required super.builder});

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 用 animation 驱动垂直偏移：
    // - 正向（push）：Offset(0, 1) → Offset.zero，从底部滑入
    // - 反向（pop / 预测返回）：Offset.zero → Offset(0, 1)，向下平移
    //
    // reverseCurve 用 easeInCubic 让收起时加速，符合「下拉收起」的物理感
    final position = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    return SlideTransition(position: position, child: child);
  }
}

/// 便捷构造函数：创建 FullPlayer 路由实例。
BottomSlideMaterialPageRoute<void> fullPlayerRoute() =>
    BottomSlideMaterialPageRoute(builder: (_) => const FullPlayer());
