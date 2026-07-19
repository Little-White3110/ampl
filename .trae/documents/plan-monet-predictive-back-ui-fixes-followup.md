# 莫奈色 + 预测性返回 + UI 修复（Followup 遗留问题）

> 本计划是 `plan-monet-predictive-back-ui-fixes.md` 7 项改动落地后的**遗留问题修复**。
> 通过 grill-me 质询确认 5 项决策，全部采用推荐方案。

## 背景与现状

7 项 UI 改造核心已实现（commit `236167d` + `d68fc64`），但 grill-me 现状审视发现 5 项遗留问题：

| # | 问题 | 严重度 | 文件 |
|---|------|--------|------|
| 1 | `_updateNotification` 仍用 `song.title`（带 .mp3 后缀），与 `_createAudioSource` 已用 `displayName` 不一致 | P0 | `lib/providers/player_provider.dart:795` |
| 2 | `album_detail_page.dart` 的 `SliverAppBar` 未实现 fade-in，与 `playlist_page.dart` 同类页设计不一致 | P1 | `lib/modules/album/album_detail_page.dart:79-175` |
| 3 | `_buildGroupSection` 的 `showAdd` 参数声明为 `required` 但函数体从未使用（dead parameter） | P1 | `lib/modules/user/favorites_page.dart:314` |
| 4 | `PopScope.onPopInvokedWithResult` 回调因 `canPop: true` 永远 `didPop==true` 直接 return，事实上空操作 | P2 | `lib/app.dart:253-261` |
| 5 | `personal_fm_page.dart` 仍用普通 `AppBar`，未跟上 discover/charts/favorites 三个 tab 的 `ScrollAwareAppBar` 渐变风格 | P2 | `lib/modules/personal_fm/personal_fm_page.dart:288` |

---

## 决策（已通过 grill-me 确认）

| # | 决策 |
|---|------|
| 1 | **修复 `_updateNotification`**：`song.title` → `song.displayName` |
| 2 | **同步实现 album 详情页 fade-in**：仿 `playlist_page.dart:392-417` |
| 3 | **删除 `showAdd` dead parameter**（含两处调用传参） |
| 4 | **删除 PopScope 空回调**：纯预测返回，栈空直接退出 |
| 5 | **统一为 `ScrollAwareAppBar`**：personal_fm_page 加 ScrollController + 替换 AppBar |

**未纳入范围（保持现状）**：
- Ticker 离屏暂停（Flutter TickerMode 通常自动处理）
- CHANGELOG.md 补记（用户未要求）
- SnackBar / downloads_provider / library_provider 搜索 中的 `song.title`（用户只要求修 MediaSession）
- 子路由页面（`_PlaylistBrowsePage` / `_DailyRecommendDetailPage` / `_RankDetailPage` 等）的 AppBar 风格统一

---

## 具体改动

### 改动 1 — 修复 MediaSession 通知标题仍带 .mp3 后缀

**文件**：`md3Music/lib/providers/player_provider.dart`

**位置**：第 794-795 行 `_updateNotification` 方法

**改动**：
```dart
// 改前
MediaNotificationService.updateNotification(
  title: song.title,        // ❌ 仍带 .mp3 后缀
  ...
)

// 改后
MediaNotificationService.updateNotification(
  title: song.displayName,  // ✅ 与 _createAudioSource 一致，去后缀
  ...
)
```

**理由**：`_createAudioSource`（第 822/832 行）已用 `song.displayName`，但 `_updateNotification`（第 795 行）漏改，导致应用内 MediaNotificationService 通知栏仍显示 `.mp3` 后缀，与 `just_audio_background` 的 MediaSession 不一致。

---

### 改动 2 — Album 详情页顶栏 fade-in（同步 playlist_page 风格）

**文件**：`md3Music/lib/modules/album/album_detail_page.dart`

**改造模板**：参照 `lib/modules/playlist/playlist_page.dart:41-69 + 392-417`

**改动内容**：

1. **State 字段**：新增 `final ScrollController _scrollController = ScrollController();` + `double _scrollOffset = 0;`
2. **_onScroll 监听器**：复制 playlist_page 的 `_onScroll`（阈值 0.5px 防抖）
3. **initState**：`_scrollController.addListener(_onScroll);`
4. **dispose**：`_scrollController.removeListener(_onScroll); _scrollController.dispose();`
5. **CustomScrollView**：`controller: _scrollController,`
6. **SliverAppBar**（第 79-175 行）新增三个属性：
   ```dart
   SliverAppBar(
     expandedHeight: 280,
     pinned: true,
     // 新增：pinned 后顶栏背景色渐变
     backgroundColor: Color.lerp(
       Colors.transparent,
       colorScheme.surface,
       (_scrollOffset - (280 - kToolbarHeight)).clamp(0.0, 60.0) / 60,
     )!,
     surfaceTintColor: Colors.transparent,
     scrolledUnderElevation: 0,
     // 新增：pinned 后顶栏标题 fade-in
     title: Opacity(
       opacity: ((_scrollOffset - (280 - kToolbarHeight)) / 60.0).clamp(0.0, 1.0),
       child: Text(
         displayAlbum.name,
         maxLines: 1,
         overflow: TextOverflow.ellipsis,
         style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
       ),
     ),
     flexibleSpace: FlexibleSpaceBar(
       background: ... // 原有内容保持不变
     ),
   )
   ```

**理由**：album 与 playlist 是同类详情页（封面 + 歌曲列表），顶栏行为应保持一致；当前 album pin 后顶栏会突变变色、无标题 fade-in，体验割裂。

**注意**：阈值魔数 `280 - kToolbarHeight` 和 `60` 与 `expandedHeight: 280` 强耦合——本次保持与 playlist_page 完全相同的硬编码方式，**不**做提取常量重构（保持两侧一致即一致性，未来若改 expandedHeight 同步两处即可）。

---

### 改动 3 — 删除 `showAdd` dead parameter

**文件**：`md3Music/lib/modules/user/favorites_page.dart`

**位置**：
- 第 307-315 行：`_buildGroupSection` 方法签名
- 第 288 行：第一处调用 `showAdd: false,`
- 第 300 行：第二处调用 `showAdd: false,`

**改动**：
```dart
// 改前
Widget _buildGroupSection({
  required String title,
  ...
  required bool showAdd,  // ❌ 函数体从未使用
}) { ... }

// 改后
Widget _buildGroupSection({
  required String title,
  ...
  // 删除 showAdd 参数
}) { ... }
```

同时删除两处调用的 `showAdd: false,` 传参。

**理由**：清理前序改动遗留的 dead parameter，避免误导后续维护者。

---

### 改动 4 — 删除 PopScope 空回调

**文件**：`md3Music/lib/app.dart`

**位置**：第 253-261 行 `_MainLayoutState.build` 中的 `PopScope`

**改动**：
```dart
// 改前
return PopScope(
  canPop: true,
  onPopInvokedWithResult: (didPop, result) {
    if (didPop) return;
    // canPop: true 时 didPop 永远为 true，不会进入此分支
    // 保留兜底：栈非空时不弹退出框
  },
  child: ResponsiveScaffold(...),
);

// 改后
// canPop: true 让系统启动边缘滑动预测动画，子路由自动 pop，
// 栈空时系统直接执行 activity back 退出 App（无确认框）
return PopScope(
  canPop: true,
  child: ResponsiveScaffold(...),
);
```

**理由**：原 `onPopInvokedWithResult` 因 `canPop: true` 永远 `didPop==true` 直接 return，事实上空操作；删除空回调减少误导（用户已确认不需要退出确认框）。

---

### 改动 5 — personal_fm_page 统一为 ScrollAwareAppBar

**文件**：`md3Music/lib/modules/personal_fm/personal_fm_page.dart`

**位置**：第 287-293 行 `Scaffold.appBar`

**改造模板**：参照 `lib/modules/discover/discover_page.dart` / `lib/modules/charts/charts_page.dart`

**改动内容**：

1. **import**：`import '../../widgets/scroll_aware_app_bar.dart';`
2. **State 字段**：新增 `final ScrollController _scrollController = ScrollController();`
3. **dispose**：`_scrollController.dispose();`（若已有 dispose 则合并）
4. **Scaffold.appBar**：
   ```dart
   // 改前
   appBar: AppBar(
     title: Text(
       '私人 FM',
       style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
     ),
   ),
   body: SingleChildScrollView(...)

   // 改后
   appBar: ScrollAwareAppBar(
     title: '私人 FM',
     scrollController: _scrollController,
   ),
   body: SingleChildScrollView(
     controller: _scrollController,  // 新增
     ...
   )
   ```

**理由**：personal_fm 是底部 5 个 tab 之一，应与 discover/charts/favorites 顶栏风格统一；当前其用普通 AppBar 在滚动时顶栏不变色，与其他 3 个 tab 视觉割裂。

**注意**：`SingleChildScrollView` 支持 `controller:` 参数，与 `ListView` 用法一致；`ScrollAwareAppBar` 的 `fadeRange` 默认 80px 对 personal_fm 内容也合适。

---

## 验证步骤

1. **静态检查**：`flutter analyze` 无错误（无未使用 import / 参数 / 变量）
2. **CI 验证**：push 后 GitHub Actions Analyze & Test Job 通过
3. **APK 安装真机验证**（v8a）：
   - **改动 1**：播放任意 .mp3 歌曲，下拉系统通知栏，标题**无 .mp3 后缀**
   - **改动 2**：进入任意专辑详情页，向上滑动至顶栏 pin，观察：
     - 顶栏背景从透明**渐变**到 surface（无突变）
     - 顶栏标题（专辑名）从无到有 **fade-in** 显示
   - **改动 3**：进入「我的收藏」tab，确认两个分组头部均无加号、列表展开/收纳动画正常
   - **改动 4**：在主 tab 页按返回键 / 边缘滑动，预测动画启动；栈空时直接退出 App（无确认框）
   - **改动 5**：在「私人 FM」tab 向上滑动，观察：
     - 顶栏背景从透明**渐变**到 surface（与 discover/charts/favorites 一致）
     - 顶栏标题「私人 FM」fade-in 显示
4. **回归**：确认其他页面（playlist 详情页、discover、charts、favorites）顶栏行为无回归

---

## 提交策略

所有 5 项改动**一次性提交**，commit message：
```
fix: resolve followup issues from monet/predictive-back/ui-fixes

- player_provider: _updateNotification use song.displayName (remove .mp3 suffix)
- album_detail_page: add SliverAppBar fade-in (sync with playlist_page)
- favorites_page: remove dead showAdd parameter
- app: remove empty PopScope.onPopInvokedWithResult callback
- personal_fm_page: use ScrollAwareAppBar (sync with other tabs)
```

push 后等待 CI 验证，通过后下载 APK 真机回归。

---

## 风险与回退

- **改动 1** 风险极低（一行替换，displayName getter 已存在并已被 `_createAudioSource` 验证）
- **改动 2** 风险中（SliverAppBar 改造，需测试 album 详情页滚动行为；若 fade-in 阈值与 expandedHeight 不匹配可能标题闪现——保持与 playlist_page 完全相同的硬编码可降低风险）
- **改动 3** 风险极低（删除未使用参数）
- **改动 4** 风险极低（删除空回调，PopScope.canPop: true 行为不变）
- **改动 5** 风险低（AppBar 替换为 ScrollAwareAppBar，加 ScrollController；若 personal_fm_page SingleChildScrollView 无 controller 入口需检查 API 兼容性——已确认 SingleChildScrollView 接受 controller）

回退策略：若任一改动出问题，单独 revert 对应文件即可（5 项改动相互独立）。
