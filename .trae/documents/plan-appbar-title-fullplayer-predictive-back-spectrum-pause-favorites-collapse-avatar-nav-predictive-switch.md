# 顶栏标题常显 + FullPlayer 预测返回 + 频谱暂停 + 收藏折叠 + 头像跳转 + 预测返回开关

> 本计划针对用户反馈的 5 项问题 + 1 项新增功能。
> 通过 grill-me 质询确认 3 项关键决策。

## 背景与现状

用户反馈 5 项问题 + 1 项新增功能，经代码探索确认根因：

| # | 问题 | 根因 | 文件 |
|---|------|------|------|
| 1 | 顶栏初始不显示文字 | `ScrollAwareAppBar` 用 `Opacity(opacity: t)` 包标题，t 从 0 开始 | `lib/widgets/scroll_aware_app_bar.dart:100-106` |
| 2 | FullPlayer 无预测返回 | `mini_player.dart:31` 路由 `opaque: false` 禁用了系统预测动画 | `lib/modules/player/mini_player.dart:27-49` |
| 3 | 暂停时频谱切固定样式 | `song_list_item.dart:228-241` 用 `if (isCurrentSong && isPlaying)` 切换 widget，而非暂停 ticker | `lib/widgets/song_list_item.dart` + `playing_spectrum_indicator.dart` |
| 4 | 收藏页折叠只藏超 5 个 | `favorites_page.dart:313` `displayCount = isExpanded ? len : (count > 5 ? 5 : count)` | `lib/modules/user/favorites_page.dart` |
| 5 | 发现页头像不可点 | `_buildAvatar` 无 GestureDetector 包裹 | `lib/modules/discover/discover_page.dart:191-230` |
| 6（新增）| 预见性返回开关 | 当前 `PopScope.canPop: true` 硬编码 | `lib/app.dart:252-253` |

**「我的」页面** `user_center_page.dart:38-81` 用普通 `AppBar`（非 `ScrollAwareAppBar`），需统一。

---

## 决策（已通过 grill-me 确认）

| # | 决策 |
|---|------|
| 头像跳转 | **方案 A：push 独立路由**（注册 `/user` 路由，头像 `GestureDetector` → `pushNamed('/user')`） |
| 开关关闭行为 | **恢复退出确认框**（`canPop: false` + `onPopInvokedWithResult` 拦截，弹「确认退出 App」对话框） |
| 频谱暂停行为 | **暂停 ticker 保留最后一帧**（不是切图标，而是 `PlayingSpectrumIndicator` 加 `isPlaying` 参数，false 时 `_ticker.stop()`，true 时 `_ticker.start()`） |

**未纳入范围（保持现状）**：
- FullPlayer 的下拉收起手势动画（与预测返回独立，不冲突）
- 其他页面的 Hero 动画（项目无 Hero 使用）
- Web/Desktop 平台兼容（PopScope 在非 Android 退化，开关无影响）

---

## 具体改动

### 改动 1 — ScrollAwareAppBar 标题始终显示

**文件**：`md3Music/lib/widgets/scroll_aware_app_bar.dart`

**位置**：第 100-106 行 `title: Opacity(...)`

**改动**：删除 `Opacity` wrapper，直接放 `Text`：
```dart
// 改前
title: Opacity(
  opacity: t,
  child: Text(
    widget.title,
    style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
  ),
),

// 改后
title: Text(
  widget.title,
  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
),
```

**理由**：用户要求标题始终显示；背景色渐变逻辑（`Color.lerp`）保留不变，仍随滚动渐变。文字颜色 `foregroundColor: colorScheme.onSurface` 在透明背景下也能看清（顶栏区域通常无内容遮挡）。

**影响范围**：4 个使用 `ScrollAwareAppBar` 的页面（discover/charts/favorites/personal_fm）标题都会立即显示——这正是用户期望。

---

### 改动 2 — 「我的」页面统一为 ScrollAwareAppBar

**文件**：`md3Music/lib/modules/user/user_center_page.dart`

**改造模板**：参照 `lib/modules/discover/discover_page.dart` / `lib/modules/charts/charts_page.dart`

**改动内容**：

1. **import**：`import '../../widgets/scroll_aware_app_bar.dart';`
2. **State 字段**：新增 `final ScrollController _scrollController = ScrollController();`
3. **dispose**：`_scrollController.dispose();`（若已有 dispose 则合并）
4. **Scaffold.appBar**：替换为 `ScrollAwareAppBar`
5. **body 的 CustomScrollView**：加 `controller: _scrollController`

**关键代码**：
```dart
// 改前（user_center_page.dart:38-50）
return Scaffold(
  appBar: AppBar(
    title: Text(
      '我的',
      style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    actions: [
      IconButton(icon: const Icon(Icons.settings), ...),
      Consumer<KugouProvider>(...),
    ],
  ),
  body: Consumer<KugouProvider>(... CustomScrollView ...),
);

// 改后
return Scaffold(
  appBar: ScrollAwareAppBar(
    title: '我的',
    scrollController: _scrollController,
    actions: [
      IconButton(icon: const Icon(Icons.settings), ...),
      Consumer<KugouProvider>(...),
    ],
  ),
  body: Consumer<KugouProvider>(
    builder: (context, kugou, _) {
      return CustomScrollView(
        controller: _scrollController,  // 新增
        ...
      );
    },
  ),
);
```

**理由**：用户要求「我的页面也统一成一样的样式」；改造后 5 个主 tab 顶栏风格完全一致（标题常显 + 背景渐变）。

**注意**：需保留原 actions 中的设置按钮和登录/登出按钮，仅替换 AppBar 外壳。

---

### 改动 3 — FullPlayer 启用预测性返回

**文件**：`md3Music/lib/modules/player/mini_player.dart`

**位置**：第 27-49 行 `Navigator.of(context).push(PageRouteBuilder(...))`

**改动**：删除 `opaque: false` 参数（改为默认 `opaque: true`）：
```dart
// 改前（mini_player.dart:27-49）
Navigator.of(context).push(
  PageRouteBuilder(
    opaque: false,                    // ← 删除
    pageBuilder: (_, _, _) => const FullPlayer(),
    transitionsBuilder: (_, animation, _, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
        ),
        child: child,
      );
    },
  ),
);

// 改后
Navigator.of(context).push(
  PageRouteBuilder(
    pageBuilder: (_, _, _) => const FullPlayer(),
    transitionsBuilder: (_, animation, _, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
        ),
        child: child,
      );
    },
  ),
);
```

**理由**：`opaque: false` 会让系统认为底层路由可见，无法预测下一层路由的渲染，从而禁用预测返回动画。FullPlayer 内部用 `Scaffold(backgroundColor: Colors.black)` + `Stack` 模糊背景层完全自包含（`full_player.dart:242-261`），不依赖底层可见 → 可安全改为 `opaque: true`。

**副作用验证**：
- 下拉收起手势 `_collapse()` 调用 `Navigator.maybePop()` 仍正常工作（与 opaque 无关）
- 路由 push/pop 的 SlideTransition 动画不变
- 全屏黑色背景仍完全覆盖底层（FullPlayer 自带黑色 Scaffold）

---

### 改动 4 — PlayingSpectrumIndicator 支持暂停

**文件**：`md3Music/lib/widgets/playing_spectrum_indicator.dart`

**改动内容**：

1. **新增 `isPlaying` 参数**（默认 true 保持向后兼容）：
```dart
class PlayingSpectrumIndicator extends StatefulWidget {
  final Color color;
  final double size;
  final bool isPlaying;  // 新增

  const PlayingSpectrumIndicator({
    super.key,
    required this.color,
    this.size = 14,
    this.isPlaying = true,  // 新增
  });

  @override
  State<PlayingSpectrumIndicator> createState() =>
      _PlayingSpectrumIndicatorState();
}
```

2. **根据 isPlaying 控制 ticker**：
```dart
class _PlayingSpectrumIndicatorState extends State<PlayingSpectrumIndicator>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.isPlaying) {
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(covariant PlayingSpectrumIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    // isPlaying 状态变化时启停 ticker
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _lastElapsed = Duration.zero;  // 重置避免 dt 跳跃
        _ticker.start();
      } else {
        _ticker.stop();
      }
    }
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
  // ... build 不变
}
```

**关键点**：
- `didUpdateWidget` 监听 isPlaying 变化，启停 ticker
- 暂停时 `_ticker.stop()` 保留最后一帧（setState 不再调用，画面冻结）
- 恢复播放时 `_lastElapsed = Duration.zero` 重置，避免 dt 跳跃

---

### 改动 5 — song_list_item.dart 统一用 PlayingSpectrumIndicator

**文件**：`md3Music/lib/widgets/song_list_item.dart`

**位置**：第 228-241 行

**改动**：删除 `else if` 分支，当前歌曲始终用 `PlayingSpectrumIndicator`，通过 `isPlaying` 参数控制动画：
```dart
// 改前（song_list_item.dart:228-241）
if (isCurrentSong && playerProvider.isPlaying)
  Padding(
    padding: const EdgeInsets.only(right: 2),
    child: PlayingSpectrumIndicator(
      color: colorScheme.primary,
      size: 14,
    ),
  )
else if (isCurrentSong)
  Padding(
    padding: const EdgeInsets.only(right: 2),
    child: Icon(Icons.equalizer, size: 13, color: colorScheme.primary),
  ),

// 改后
if (isCurrentSong)
  Padding(
    padding: const EdgeInsets.only(right: 2),
    child: PlayingSpectrumIndicator(
      color: colorScheme.primary,
      size: 14,
      isPlaying: playerProvider.isPlaying,  // 暂停时停止动画
    ),
  ),
```

**理由**：用户原话「暂停音乐时暂停频谱图标的动画播放，继续播放音乐的时候继续播放频谱动画」——即保留 widget 但暂停动画，而非切换为静态图标。

---

### 改动 6 — 收藏页折叠全部隐藏

**文件**：`md3Music/lib/modules/user/favorites_page.dart`

**位置**：第 313 行

**改动**：
```dart
// 改前
final displayCount = isExpanded ? playlists.length : (count > 5 ? 5 : count);

// 改后
// 折叠时全部隐藏，展开时显示全部
final displayCount = isExpanded ? playlists.length : 0;
```

**理由**：用户原话「折叠的时候只能折叠超出5个的部分，修复成所有的都能够折叠」——即折叠时显示 0 个，展开时显示全部。

**副作用处理**：
- `List.generate(0, ...)` 返回空列表 → `Column(children: [])` 高度为 0 → `AnimatedSize` 平滑收缩
- 分组头部 + 计数标签仍可见
- 管理模式下若用户已选中歌单后折叠，`_selectedIndices` 仍保留——已有 `_selectedIndices.isEmpty ? null : ...` 保护批量删除按钮（line 345-350），无逻辑问题

---

### 改动 7 — 发现页头像跳转「我的」页面

**文件**：
- `md3Music/lib/app.dart`（注册路由）
- `md3Music/lib/modules/discover/discover_page.dart`（头像点击）

**改动内容**：

1. **app.dart 注册 `/user` 路由**（在 `routes:` 中新增）：
```dart
routes: {
  '/': (_) => const _MainLayout(),
  '/search': (_) => const SearchPage(),
  '/library': (_) => const LibraryPage(),
  '/settings': (_) => const SettingsPage(),
  '/user': (_) => const UserCenterPage(),  // 新增
  '/player': (_) => const FullPlayer(),
  '/personal_fm': (_) => const PersonalFmPage(),
},
```

2. **discover_page.dart 头像包 GestureDetector**：
```dart
// 改前（discover_page.dart:152-157 + 191-230）
Consumer<KugouProvider>(
  builder: (context, kugou, _) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: _buildAvatar(kugou, colorScheme),
  ),
),

// 改后
Consumer<KugouProvider>(
  builder: (context, kugou, _) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GestureDetector(
      onTap: () => Navigator.of(context).pushNamed('/user'),
      child: _buildAvatar(kugou, colorScheme),
    ),
  ),
),
```

**理由**：方案 A 简单且符合现有 `/settings`、`/search` 导航模式；UserCenterPage 是 StatefulWidget 无全局状态，多实例无冲突。

---

### 改动 8 — ThemeProvider 新增 predictiveBackEnabled 字段

**文件**：`md3Music/lib/providers/theme_provider.dart`

**改动内容**：

1. **新增字段与持久化**：
```dart
static const String _predictiveBackKey = 'predictive_back_enabled';
bool _predictiveBackEnabled = true;  // 默认开启

bool get predictiveBackEnabled => _predictiveBackEnabled;

Future<void> _loadPredictiveBack() async {
  final prefs = await SharedPreferences.getInstance();
  _predictiveBackEnabled = prefs.getBool(_predictiveBackKey) ?? true;
  notifyListeners();
}

Future<void> setPredictiveBackEnabled(bool enabled) async {
  if (_predictiveBackEnabled == enabled) return;
  _predictiveBackEnabled = enabled;
  notifyListeners();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_predictiveBackKey, enabled);
}
```

2. **构造函数调用 `_loadPredictiveBack()`**：
```dart
ThemeProvider() {
  _loadThemeMode();
  _loadDynamicColor();
  _loadPredictiveBack();  // 新增
}
```

**理由**：参考现有 `_useDynamicColor` 模式，保持代码风格一致；放在 ThemeProvider 中而非新建 SettingsProvider，避免过度工程化。

---

### 改动 9 — app.dart PopScope 读取开关 + 恢复退出确认框

**文件**：`md3Music/lib/app.dart`

**位置**：第 247-254 行 `_MainLayoutState.build`

**改动内容**：

1. **恢复 `_showExitDialog` 方法**（之前 commit `236167d` 删除了，现在开关关闭时需要）：
```dart
Future<void> _showExitDialog() async {
  final shouldExit = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('退出应用'),
      content: const Text('确定要退出 MD3Music 吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('退出'),
        ),
      ],
    ),
  );
  if (shouldExit == true && mounted) {
    SystemNavigator.pop();
  }
}
```

2. **build 中 watch ThemeProvider + 动态 canPop**：
```dart
@override
Widget build(BuildContext context) {
  // 读取预见性返回开关：true 时系统启动预测动画 + canPop；false 时拦截弹退出框
  final predictiveBackEnabled = context.watch<ThemeProvider>().predictiveBackEnabled;
  return PopScope(
    canPop: predictiveBackEnabled,
    onPopInvokedWithResult: (didPop, result) {
      // canPop: false 时 didPop 为 false，进入此分支
      if (!didPop) {
        _showExitDialog();
      }
    },
    child: ResponsiveScaffold(...),
  );
}
```

3. **import**：恢复 `import 'package:flutter/services.dart';`（`SystemNavigator` 需要）

**理由**：
- 开关开启（默认）：`canPop: true` 启用预测返回手势，栈空直接退出（用户已确认不需要确认框）
- 开关关闭：`canPop: false` 禁用预测动画，栈空时 `onPopInvokedWithResult` 被调用（`didPop: false`），弹退出确认框
- `context.watch<ThemeProvider>()` 让开关切换时 PopScope 重建，立即生效

---

### 改动 10 — SettingsPage 新增「预见性返回手势」开关

**文件**：`md3Music/lib/modules/settings/settings_page.dart`

**改动内容**：

1. **State 新增字段**：`bool _predictiveBackEnabled = true;`

2. **_loadSettings 同步**：
```dart
_predictiveBackEnabled = context.read<ThemeProvider>().predictiveBackEnabled;
```

3. **_buildAppearanceSection 新增 SwitchListTile**（紧跟「使用系统主题色」开关后）：
```dart
SwitchListTile(
  title: const Text('预见性返回手势'),
  subtitle: const Text('Android 14+ 边缘滑动预测动画，关闭后改为退出确认框'),
  value: _predictiveBackEnabled,
  onChanged: (v) {
    setState(() => _predictiveBackEnabled = v);
    context.read<ThemeProvider>().setPredictiveBackEnabled(v);
  },
),
```

**理由**：参考现有「使用系统主题色」开关模式，UI 风格统一。

---

## 验证步骤

1. **静态检查**：CI Analyze & Test Job 通过
2. **APK 真机验证**（用户自测）：
   - **改动 1+2**：进入 5 个主 tab（发现/排行/收藏/私人FM/我的），确认顶栏标题**始终可见**，滚动时背景色从透明渐变到 surface
   - **改动 3**：从 mini player 点开 FullPlayer，从屏幕边缘滑动，应有预测返回动画（看到 FullPlayer 跟随手指下滑）
   - **改动 4+5**：播放某首歌 → 进入歌单列表 → 暂停 → 频谱动画**停在最后一帧**；继续播放 → 频谱动画恢复
   - **改动 6**：我的收藏页 → 折叠分组 → **全部歌单隐藏**（仅剩分组头部+计数）；展开 → 显示全部
   - **改动 7**：发现页右上角头像 → 点击 → 跳转到「我的」页面（push 新页面，可返回）
   - **改动 8+9+10**：设置页 → 关闭「预见性返回手势」开关 → 按返回键 → 弹出「退出应用」确认框；重新开启 → 按返回键 → 直接退出无确认框；开启时边缘滑动有预测动画

3. **回归**：
   - FullPlayer 下拉收起手势仍正常工作（`_collapse()` 与 opaque 无关）
   - Mini player 点击仍能 push FullPlayer
   - 其他路由（/search /settings /playlist）顶栏行为无回归

---

## 提交策略

所有改动**一次性提交**，commit message：
```
feat: always-show appbar title + fullplayer predictive back + spectrum pause + favorites collapse all + avatar nav + predictive back switch

- scroll_aware_app_bar: remove Opacity wrapper, title always visible
- user_center_page: switch to ScrollAwareAppBar (sync with other tabs)
- mini_player: remove opaque:false to enable predictive back on FullPlayer
- playing_spectrum_indicator: add isPlaying param, stop ticker when paused
- song_list_item: always use PlayingSpectrumIndicator, pass isPlaying
- favorites_page: collapse all playlists when folded (displayCount = 0)
- discover_page: avatar tap navigates to /user route
- app.dart: register /user route, PopScope reads predictiveBackEnabled switch
- theme_provider: add predictiveBackEnabled field with persistence
- settings_page: add '预见性返回手势' switch (default on)
```

push 后等待 CI 验证，通过后下载 APK 用户自测。

---

## 风险与回退

| 改动 | 风险 | 回退 |
|------|------|------|
| 1（标题常显）| 极低 | 恢复 Opacity wrapper |
| 2（我的页改造）| 低 | 恢复普通 AppBar |
| 3（opaque: true）| 中（需验证 FullPlayer 视觉无底层透出）| 恢复 opaque: false |
| 4+5（频谱暂停）| 低 | 恢复 if/else 分支 |
| 6（折叠全部）| 极低 | 恢复 `count > 5 ? 5 : count` |
| 7（头像跳转）| 低（UserCenterPage 多实例无冲突）| 删除 /user 路由 + GestureDetector |
| 8+9+10（开关）| 低 | 删除字段 + 恢复 canPop: true |

**关键风险点**：改动 3 的 `opaque: true` 是唯一中等风险项——若 FullPlayer 的下拉收起动画依赖底层可见（如半透明过渡），可能视觉异常。但探索确认 FullPlayer 自带黑色 Scaffold + 模糊背景层，完全自包含，预期无问题。若出问题可单独回退改动 3。
