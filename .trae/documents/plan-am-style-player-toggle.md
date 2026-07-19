# Apple Music 风格播放页开关（AM 风格 ↔ 原版 MD3 切换）

> 本计划通过 grill-me 质询确认 4 项关键决策。
> 原仓库已克隆到 `c:\Users\32732\Downloads\md3music-original\`。

## 背景与现状

用户当前 ampl 项目的 FullPlayer 已重度改造为 Apple Music 风格（模糊封面背景 + 弹簧动画 + AppleLyricsView 逐字歌词 + 白色主题 + 下拉手柄等）。原版 md3Music 的 FullPlayer 是标准 MD3 风格（简单 SafeArea + Column + LyricsView 行级滚动 + 主题色）。

用户希望把 AM 风格做成**可选功能**，设置页加开关，**默认关闭**，关闭时用原版 MD3 实现，开启时才用 AM 风格。

### 原仓库信息

- **原仓库地址**：https://github.com/zzyoxml/md3Music
- **克隆位置**：`c:\Users\32732\Downloads\md3music-original\`
- **ampl 当前位置**：`c:\Users\32732\Desktop\TRAE SOLO\ampl\md3Music\`

### 关键差异清单（grill-me 调研结果）

| 特性 | AM 风格（ampl 当前） | 原版 MD3 |
|------|---------------------|---------|
| 背景层 | 模糊封面 + 黑蒙版 | 无 |
| 展开动画 | Spring 弹簧 + Ticker | 无 |
| 歌词 | AppleLyricsView（KRC 逐字 + 间奏点） | LyricsView（LRC 行级滚动） |
| 主题色 | 全白 | colorScheme 标准 MD3 |
| 播放按钮 | 白色圆形 IconButton.filled | 标准 MD3 |
| 下拉手柄 | 40×4 白色胶囊 | 无（用 Icons.keyboard_arrow_down） |
| 顶部栏 | 自定义白色 | 标准 MD3 |
| Mixin | TickerProviderStateMixin | SingleTickerProviderStateMixin |
| 行数 | 1585 行 | 1193 行 |

### 文件依赖关系

- AM 风格 FullPlayer 独占依赖：`lib/widgets/apple_lyrics/` 整目录、`Spring` 类、`LyricPreferencesPanel`
- 原版 FullPlayer 独占依赖：`lib/modules/player/lyrics_view.dart`（ampl 已删除，需恢复）
- 两者共享：`Song` model（ampl additive 新增 `displayName` getter 不破坏原版）、`KugouProvider`（`displayLyric` 兼容 LRC 降级）

---

## 决策（已通过 grill-me 质询确认）

| # | 决策 |
|---|------|
| P1 默认状态 | **默认关闭**（保持当前体验需用户主动开启；符合「新增功能默认不启用」原则） |
| P2 原版歌词 | **原版保持原貌**（用 LRC 行级 LyricsView，不加 KRC 逐字支持；改动量最小） |
| P3 切换生效 | **下次打开生效**（已 push 的 FullPlayer 不变，下次点 MiniPlayer 走新分支；简单可靠） |
| P4 原版路由 | **统一用 BottomSlideMaterialPageRoute**（两个版本都从底部滑入 + 支持预测返回；体验一致） |

**未纳入范围（保持现状）**：
- AM 风格独有特性不改动（apple_lyrics 模块、Spring 动画等保持原样）
- KugouProvider 不改动（KRC 支持保留，原版 FullPlayer 自动降级用 LRC）
- Song model 不改动（`displayName` 是 additive，不破坏原版）
- 原版 LyricsView 不加 KRC 支持（保持原版原貌）

---

## 具体改动

### 改动 1 — 重命名 AM 风格 FullPlayer 文件与类名

**操作**：
- 复制 `c:\Users\32732\Desktop\TRAE SOLO\ampl\md3Music\lib\modules\player\full_player.dart` → `lib\modules\player\full_player_am.dart`
- 在新文件中：类名 `FullPlayer` → `AmStyleFullPlayer`

**理由**：保留 AM 风格代码不删除，仅重命名让原版代码可以恢复 `full_player.dart` 文件名。

**关键改动**：
```dart
// full_player_am.dart 顶部
class AmStyleFullPlayer extends StatefulWidget {  // 改名
  const AmStyleFullPlayer({super.key});
  @override
  State<AmStyleFullPlayer> createState() => _AmStyleFullPlayerState();  // 改名
}

class _AmStyleFullPlayerState extends State<AmStyleFullPlayer>  // 改名
    with TickerProviderStateMixin { ... }
```

**注意**：
- State 类 `_FullPlayerState` → `_AmStyleFullPlayerState`
- 文件内所有引用 `FullPlayer` 类名的地方都要改为 `AmStyleFullPlayer`
- 文件末尾可能有其他类（如 `_buildMiniBar` 的辅助类）也要检查

---

### 改动 2 — 从原仓库恢复原版 FullPlayer 到 full_player.dart

**操作**：复制 `c:\Users\32732\Downloads\md3music-original\lib\modules\player\full_player.dart` → `c:\Users\32732\Desktop\TRAE SOLO\ampl\md3Music\lib\modules\player\full_player.dart`

**注意**：原版 FullPlayer 的类名仍是 `FullPlayer`，与 AM 风格的 `AmStyleFullPlayer` 区分。

**潜在兼容性问题**：
- 原版 `full_player.dart` 调用 `CommentsView(songHash: ..., albumAudioId: ...)` 不传 `artworkUri`
- ampl 版 `CommentsView` 已有 `artworkUri` 参数（已是可选命名参数 `String? artworkUri`），原版不传也能用 ✅
- 原版用 `currentSong.title`，ampl 的 `Song.displayName` getter 是 additive，不影响 ✅
- 原版用 `KugouProvider.lyric?.displayLyric ?? ''`，ampl 的 `displayLyric` 兼容 LRC 降级 ✅

---

### 改动 3 — 从原仓库恢复 lyrics_view.dart

**操作**：复制 `c:\Users\32732\Downloads\md3music-original\lib\modules\player\lyrics_view.dart` → `c:\Users\32732\Desktop\TRAE SOLO\ampl\md3Music\lib\modules\player\lyrics_view.dart`

**理由**：原版 FullPlayer 依赖 LyricsView widget，ampl 之前删除了，需恢复。

**验证**：原版 `full_player.dart` 的 import 应该有 `import 'lyrics_view.dart';`，恢复后即可正常引用。

---

### 改动 4 — ThemeProvider 新增 useAmStylePlayer 字段

**文件**：`md3Music/lib/providers/theme_provider.dart`

**改动内容**：参考现有 `_predictiveBackEnabled` 模式新增字段。

```dart
static const String _amStylePlayerKey = 'use_am_style_player';
bool _useAmStylePlayer = false;  // 默认关闭，需用户主动开启

bool get useAmStylePlayer => _useAmStylePlayer;

Future<void> _loadAmStylePlayer() async {
  final prefs = await SharedPreferences.getInstance();
  _useAmStylePlayer = prefs.getBool(_amStylePlayerKey) ?? false;
  notifyListeners();
}

Future<void> setUseAmStylePlayer(bool enabled) async {
  if (_useAmStylePlayer == enabled) return;
  _useAmStylePlayer = enabled;
  notifyListeners();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_amStylePlayerKey, enabled);
}
```

**构造函数**：新增 `_loadAmStylePlayer();` 调用。

```dart
ThemeProvider() {
  _loadThemeMode();
  _loadDynamicColor();
  _loadPredictiveBack();
  _loadAmStylePlayer();  // 新增
}
```

---

### 改动 5 — full_player_route.dart 根据开关选择 widget

**文件**：`md3Music/lib/modules/player/full_player_route.dart`

**改动内容**：`fullPlayerRoute()` 函数加 `BuildContext` 参数，根据 `ThemeProvider.useAmStylePlayer` 选择 widget。

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import 'full_player.dart';
import 'full_player_am.dart';

/// 从底部滑入的 [MaterialPageRoute] 子类（不变）
class BottomSlideMaterialPageRoute<T> extends MaterialPageRoute<T> {
  BottomSlideMaterialPageRoute({required super.builder});

  @override
  Widget buildTransitions(...) {
    // ... 保持原样
  }
}

/// 根据 ThemeProvider.useAmStylePlayer 开关选择 FullPlayer 实现。
/// - false（默认）：原版 MD3 风格 FullPlayer
/// - true：Apple Music 风格 AmStyleFullPlayer
///
/// 切换开关后，已 push 的路由不会自动换 widget，下次 push 时才走新分支
/// （符合「设置项」预期，实现简单可靠）。
BottomSlideMaterialPageRoute<void> fullPlayerRoute(BuildContext context) {
  final useAm = context.read<ThemeProvider>().useAmStylePlayer;
  return BottomSlideMaterialPageRoute(
    builder: (_) => useAm ? const AmStyleFullPlayer() : const FullPlayer(),
  );
}
```

---

### 改动 6 — mini_player.dart 调用 fullPlayerRoute(context)

**文件**：`md3Music/lib/modules/player/mini_player.dart`

**位置**：第 28-36 行附近

**改动**：
```dart
// 改前
Navigator.of(context).push(fullPlayerRoute());

// 改后
Navigator.of(context).push(fullPlayerRoute(context));
```

**import 更新**：
```dart
// 改前
import 'full_player_route.dart';

// 改后（不变，仍只需 full_player_route.dart）
import 'full_player_route.dart';
```

注意：`full_player.dart` 和 `full_player_am.dart` 都由 `full_player_route.dart` 内部引用，`mini_player.dart` 不直接 import。

---

### 改动 7 — SettingsPage 新增「Apple Music 风格播放页」开关

**文件**：`md3Music/lib/modules/settings/settings_page.dart`

**改动内容**：参考现有「预见性返回手势」开关模式新增。

1. **State 新增字段**：`bool _useAmStylePlayer = false;`

2. **_loadSettings 同步**：
```dart
final useAm = context.read<ThemeProvider>().useAmStylePlayer;
// ...
setState(() {
  // ...
  _useAmStylePlayer = useAm;
});
```

3. **_buildAppearanceSection 新增 SwitchListTile**（紧跟「预见性返回手势」开关后）：
```dart
SwitchListTile(
  title: const Text('Apple Music 风格播放页'),
  subtitle: const Text('使用模糊封面背景 + 弹簧动画 + 逐字歌词（关闭则用原版 MD3 风格）'),
  value: _useAmStylePlayer,
  onChanged: (v) {
    setState(() => _useAmStylePlayer = v);
    context.read<ThemeProvider>().setUseAmStylePlayer(v);
  },
),
```

---

## 验证步骤

1. **静态检查**：CI Analyze & Test Job 通过
2. **APK 真机验证**（用户自测）：
   - **默认状态**：首次安装 → 设置页确认「Apple Music 风格播放页」开关**关闭** → 点 MiniPlayer 打开 FullPlayer → 应显示**原版 MD3 风格**（无模糊背景、无弹簧动画、LRC 行级歌词、标准 MD3 主题色）
   - **开启 AM 风格**：设置页打开开关 → 返回 → 点 MiniPlayer → 应显示**AM 风格**（模糊封面背景、弹簧动画、KRC 逐字歌词、白色主题、下拉手柄）
   - **关闭 AM 风格**：设置页关闭开关 → 返回 → 点 MiniPlayer → 应切回**原版 MD3 风格**
   - **预测返回**：两个版本都应支持预测返回手势（FullPlayer 跟随手势向下平移）
   - **持久化**：杀进程重启 App → 开关状态保留
   - **歌词功能**：
     - 原版：LRC 行级滚动 + seek 跳转
     - AM 风格：KRC 逐字 + 间奏点 + 字号/行距设置面板

3. **回归**：
   - MiniPlayer 行为不变（仍显示 displayName）
   - MediaSession 标题不变（仍用 displayName 无 .mp3）
   - 其他页面（发现/排行/收藏/我的）不受影响

---

## 提交策略

所有改动**一次性提交**，commit message：
```
feat: add Apple Music style player toggle (default off, restore original MD3 player)

- full_player_am: rename current AM-style FullPlayer to AmStyleFullPlayer
- full_player: restore original MD3-style FullPlayer from upstream md3Music
- lyrics_view: restore original LyricsView (LRC line-level, no KRC)
- theme_provider: add useAmStylePlayer field with persistence (default false)
- full_player_route: fullPlayerRoute(context) selects widget by switch
- mini_player: pass context to fullPlayerRoute
- settings_page: add 'Apple Music 风格播放页' SwitchListTile
```

push 后等待 CI 验证，通过后用户自测。

---

## 风险与回退

| 改动 | 风险 | 回退 |
|------|------|------|
| 1（重命名 AM 类）| 低（仅改名）| 改回 FullPlayer |
| 2（恢复原版 full_player.dart）| 中（需验证原版与 ampl 的 KugouProvider/Song 兼容）| 删除文件，从 git 恢复 AM 风格 |
| 3（恢复 lyrics_view.dart）| 低（独立文件）| 删除文件 |
| 4（ThemeProvider 加字段）| 极低 | 删除字段 |
| 5（full_player_route 改函数签名）| 低（加 BuildContext 参数）| 改回无参版本 |
| 6（mini_player 加 context）| 极低 | 改回无参调用 |
| 7（设置页加开关）| 极低 | 删除 SwitchListTile |

**关键风险点**：改动 2 恢复原版 FullPlayer 后，原版代码可能与 ampl 的某些改动有微妙不兼容（如 KugouProvider 字段名变化、Song model 新增字段原版未用等）。需 CI analyze 通过 + 真机测试原版功能正常。

**回退方案**：如果原版 FullPlayer 有问题，可以临时把 `useAmStylePlayer` 默认值改为 `true`，让用户继续用 AM 风格，同时修复原版兼容性问题。

---

## 关键文件路径速查

**需修改**：
- `c:\Users\32732\Desktop\TRAE SOLO\ampl\md3Music\lib\modules\player\full_player.dart`（恢复原版）
- `c:\Users\32732\Desktop\TRAE SOLO\ampl\md3Music\lib\modules\player\full_player_am.dart`（新建，AM 风格重命名）
- `c:\Users\32732\Desktop\TRAE SOLO\ampl\md3Music\lib\modules\player\lyrics_view.dart`（新建，恢复原版）
- `c:\Users\32732\Desktop\TRAE SOLO\ampl\md3Music\lib\modules\player\full_player_route.dart`（改函数签名）
- `c:\Users\32732\Desktop\TRAE SOLO\ampl\md3Music\lib\modules\player\mini_player.dart`（加 context 参数）
- `c:\Users\32732\Desktop\TRAE SOLO\ampl\md3Music\lib\providers\theme_provider.dart`（加字段）
- `c:\Users\32732\Desktop\TRAE SOLO\ampl\md3Music\lib\modules\settings\settings_page.dart`（加开关）

**源文件（从原仓库复制）**：
- `c:\Users\32732\Downloads\md3music-original\lib\modules\player\full_player.dart`
- `c:\Users\32732\Downloads\md3music-original\lib\modules\player\lyrics_view.dart`
