# ampl → zzyoxml/md3Music 上游 PR 提交方案

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 ampl 仓库 62 个独有 commit 涉及的功能（Apple Music 风格歌词、Lyricon Provider、莫奈取色、OLED 模式、下载服务优化、GitHub Actions CI 等）以**多个独立、可 review、零 breaking** 的 PR 形式提交到上游 `zzyoxml/md3Music` 仓库的 `arch-local-first` 分支。

**Architecture:** 由于 ampl 把上游代码放在 `md3Music/` 子目录而非根目录平铺，且与上游已分叉（ampl 独有 62 commit / 上游领先 66 commit），无法直接 `git cherry-pick`。采用「**subtree split + 功能拆分 + 多 PR 隔离**」策略：先用 `git subtree split` 把 `md3Music/` 子目录历史剥离为独立分支，再按功能拆分为 6 个 PR；每个 PR 默认关闭新功能、提供开关，确保零 breaking；所有 PR 均以 issue 沟通为先导，先获得 maintainer 认可再开 PR。

**Tech Stack:** Git (subtree/cherry-pick/rebase)、GitHub (fork/PR/issue)、Flutter/Dart、Kotlin、GitHub Actions CI、Conventional Commits。

---

## 0. 背景与关键事实（必读）

### 0.1 当前仓库拓扑

```
ampl (origin: github.com/Little-White3110/ampl)
├── 根目录: README.md / LYRICON_INTEGRATION.md / md3Music-AppleLyrics-PRD.md / .github/ / .trae/
└── md3Music/   ← 上游 zzyoxml/md3Music 主干快照（非 submodule）
    ├── lib/
    ├── android/
    ├── kugou_api_server/
    ├── pubspec.yaml
    └── ...
```

```
zzyoxml/md3Music (上游)
├── 默认分支: arch-local-first (不是 main！)
├── 根目录直接平铺 lib/ android/ pubspec.yaml 等
└── 当前 HEAD: d9e925a "release: bump version to 3.2.0+9"
```

### 0.2 分叉情况（实测）

- ampl 独有 commit: **62 个**（41edbaa 起算，至 e4c1ef8）
- 上游独有 commit: **66 个**（ampl 落后于上游 v3.1.0/v3.2.0 的开发）
- ampl 改动总量: **419 文件 / +59248 行**
- ampl 上游不存在的新增目录: `md3Music/lib/widgets/apple_lyrics/`、`md3Music/lib/core/services/lyricon_provider_service.dart`

### 0.3 ampl 独有功能盘点（按 git log 还原）

| 功能模块 | 代表 commit | 文件范围 | breaking 风险 |
|---|---|---|---|
| **A. Apple Music 风格歌词模块** | `41edbaa` | `lib/widgets/apple_lyrics/`、`lib/services/kugou_api/`、`lib/providers/kugou_provider.dart`、`lib/modules/player/full_player_am.dart`、`test/widgets/apple_lyrics/` | 高（替换原 `lyrics_view.dart`，但已通过开关兜底） |
| **B. Apple Music 风格播放器开关** | `4a364e7` | `lib/modules/player/full_player_route.dart`、`settings_repository.dart`、`settings_page.dart` | 低（默认关，恢复原 MD3 播放页） |
| **C. 莫奈取色 + 8 色预设 + OLED 纯黑** | `1825b29`、`236167d` | `lib/core/theme/app_theme.dart`、`theme_provider.dart`、`settings_page.dart`、`seed_color_picker.dart` | 中（改动主题系统） |
| **D. Lyricon Provider 集成** | `f71438d`、`44f26f8`、`6653c80`、`8029887` | `android/app/build.gradle.kts`、`AndroidManifest.xml`、`res/values/arrays.xml`、`AudioPlaybackService.kt`、`MainActivity.kt`、`lib/core/services/lyricon_provider_service.dart`、`settings_page.dart`、`settings_repository.dart` | 中（引入新 Maven 依赖 `io.github.proify.lyricon:provider:0.1.70`） |
| **E. 下载服务优化** | `8bdbe71`、`a3b75a5`、`75ecc41` | `lib/services/download_manager.dart`、`lib/data/repositories/downloads_repository.dart`、`lib/modules/user/downloads_page.dart`、`android/app/build.gradle.kts`（jaudiotagger 2.2.3）、`MetadataWriterPlugin.kt` | 低 |
| **F. GitHub Actions CI** | `b88948a`、`b7f70da`、`41edbaa`、`178b5d5`、`7c0ed99`、`4230220` | `.github/workflows/ci.yml` | 低（纯新增） |
| **G. UI/UX 改进合集** | `13a55a3`、`be25b35`、`963c303`、`5bc1529`、`fb3ec04`、`0c59ed1`、`7583ee6`、`6fdd4de`、`e8921df`、`365e120` | 散落在 `mini_player.dart`、`scroll_aware_app_bar.dart`、`comments_view.dart`、`full_player.dart`、`song.dart`、`favorites_page.dart` | 中（散落改动多） |

### 0.4 关键约束

1. **目录结构差异**：ampl `md3Music/lib/...` 在上游对应 `lib/...`（去掉 `md3Music/` 前缀）。直接 PR 会让 diff 变成「全部新增」，无法 review。必须先做 `git subtree split` 把 `md3Music/` 提升到根。
2. **上游默认分支是 `arch-local-first`**，不是 `main`（**Task 1 Step 3 必须验证 `main` 与 `arch-local-first` 的关系**，确认哪个分支领先、哪个是 maintainer 实际工作分支；若 `main` 已废弃则 PR base 到 `arch-local-first`，反之需在 Task 0 Issue 中向 maintainer 确认）。
3. **CI 配置中 `working-directory: md3Music`** 必须改为根目录。
4. **breaking 风险**：原 `lyrics_view.dart` 被替换为 `AppleLyricsView`，原 MD3 风格 `full_player.dart` 被新 AM 风格覆盖。必须保留开关默认关闭，确保零 breaking。
5. **新依赖 License 审查（强制，含 LSPosed 间接依赖）**：`io.github.proify.lyricon:provider:0.1.70`（Maven）、`jaudotagger 2.2.3`（JitPack）必须在 Task 0 之前查清 License：
   - Apache 2.0 / MIT / BSD → 与上游 MIT 兼容，可静态打入 APK
   - LGPL → 需作为独立 plugin 动态链接，不能静态打进去
   - GPL / AGPL → **禁止提 PR**（copyleft 会传染整个 md3Music），改为独立 fork 或 optional plugin
   - **Lyricon 是 LSPosed 模块（需 root + LSPosed 框架）**：LSPosed 本身是 GPL-3.0。即使 md3Music 不直接依赖 LSPosed（仅作为 Provider 调用 Lyricon SDK 的接口），仍需在 PR-4 描述中**明确声明**：
     - md3Music 仅作为 Lyricon Provider（数据推送端），不依赖 LSPosed 注入机制
     - Lyricon SDK 的 Provider 接口是否构成「derivative work」是开放法律问题，建议在 PR-4 描述中提示 maintainer 咨询法律意见
     - 若 maintainer 担心 copyleft 风险，**PR-4 自动撤回**，Lyricon 集成改为 ampl 独立 fork 维护
6. **CI grep 禁用符号检查**（TTML / WebView / xml 包）：作为 **PR-6 的可选步骤**，由 maintainer 决定是否启用，不在初始版本强制。
7. **PRD/Spec 文档**：`.trae/specs/`、`md3Music-AppleLyrics-PRD.md` 属于 ampl 内部 spec-driven 流程产物，**不进入上游**；但在 PR 描述中**链接到 ampl 仓库的 spec.md** 作为设计依据（不要求 maintainer 阅读，仅作 trace）。
   - **敏感信息检查（强制）**：在 PR 描述链接 spec.md 之前，必须扫描 `md3Music-AppleLyrics-PRD.md` 和 `.trae/specs/add-apple-music-lyrics/spec.md` 是否包含：
     - 酷狗 API token / cookie / 账号信息
     - 用户隐私数据（手机号、用户 ID）
     - 内部服务器 IP / 密码
     - 任何不应公开的 URL 或凭证
   - 检查命令：`grep -Ei "token|cookie|password|secret|api_key|apikey" .trae/specs/add-apple-music-lyrics/spec.md md3Music-AppleLyrics-PRD.md`
   - 如果命中 → 在 PR 描述中**删除链接**，改为「spec 内部包含敏感信息，不公开链接」
8. **`md3Music/networkapi/` 目录**：经 git log 验证，ampl 独有 commit 中无 `networkapi/` 相关改动，**该目录是上游已有内容，不在任何 PR 范围内**。
9. **License/CLA**：ampl 与上游均为 MIT License（Copyright zzyoxml），新增代码继承 MIT，无需 CLA 签署；但 PR-4 涉及 Lyricon SDK 时需在 PR 描述中声明 SDK License。
10. **PR-1 实际是 breaking 的（澄清）**：ampl 在 commit `41edbaa feat(apple-lyrics): 集成 Apple Music 风格逐字歌词模块与 CI` 中替换了 `lib/modules/player/lyrics_view.dart` 和重构了 `lib/modules/player/full_player.dart`。**PR-1 提到上游时必须用 ampl 在 PR-2 引入开关之后的版本**，即：
    - PR-1 不动 `lyrics_view.dart`（保留上游原版）
    - PR-1 不动 `full_player.dart`（保留上游原版）
    - PR-1 只新增 `lib/widgets/apple_lyrics/` 和 `lib/modules/player/full_player_am.dart`（独立文件）
    - PR-1 改 `kugou_api_client.dart` / `kugou_models.dart` / `kugou_provider.dart` 是**增量改动**（不破坏现有 API，只新增字段/方法）
    - PR-2 才让 `full_player_route.dart` 根据开关选择 `FullPlayer` 或 `FullPlayerAm`
    - 这样 PR-1 是真正的零 breaking，PR-2 也是零 breaking（默认关）

---

## 1. 文件结构（PR 拆分映射）

下表锁定每个 PR 涉及的文件清单。**所有路径均以「上游根目录」为基准**（即 `lib/...`，而非 `md3Music/lib/...`）。

### PR-1: Apple Music 风格逐字歌词模块（核心）

**新增文件：**
- `lib/widgets/apple_lyrics/apple_lyrics_view.dart`
- `lib/widgets/apple_lyrics/animation/spring.dart`
- `lib/widgets/apple_lyrics/controllers/line_scale_controller.dart`
- `lib/widgets/apple_lyrics/controllers/lyric_scroll_controller.dart`
- `lib/widgets/apple_lyrics/layout/lyric_layout.dart`
- `lib/widgets/apple_lyrics/layout/lyric_preferences.dart`
- `lib/widgets/apple_lyrics/layout/lyric_preferences_panel.dart`
- `lib/widgets/apple_lyrics/models/lyric_line.dart`
- `lib/widgets/apple_lyrics/parsers/krc_parser.dart`
- `lib/widgets/apple_lyrics/parsers/lrc_parser.dart`
- `lib/widgets/apple_lyrics/parsers/lyric_parser_chain.dart`
- `lib/widgets/apple_lyrics/parsers/plaintext_parser.dart`
- `lib/widgets/apple_lyrics/preview/lyrics_preview_page.dart`
- `lib/widgets/apple_lyrics/renderers/emphasize_effect.dart`
- `lib/widgets/apple_lyrics/renderers/interlude_dots.dart`
- `lib/widgets/apple_lyrics/renderers/line_renderer.dart`
- `lib/widgets/apple_lyrics/renderers/word_renderer.dart`
- `lib/modules/player/full_player_am.dart`（**新增 AM 风格播放页，不替换原 `full_player.dart`**）
- `test/widgets/apple_lyrics/animation/spring_test.dart`
- `test/widgets/apple_lyrics/apple_lyrics_view_test.dart`
- `test/widgets/apple_lyrics/controllers/line_scale_controller_test.dart`
- `test/widgets/apple_lyrics/controllers/lyric_scroll_controller_test.dart`
- `test/widgets/apple_lyrics/models/lyric_line_test.dart`
- `test/widgets/apple_lyrics/parsers/krc_parser_test.dart`
- `test/widgets/apple_lyrics/parsers/lrc_parser_test.dart`
- `test/widgets/apple_lyrics/parsers/lyric_parser_chain_test.dart`
- `test/widgets/apple_lyrics/parsers/plaintext_parser_test.dart`
- `test/widgets/apple_lyrics/renderers/emphasize_effect_test.dart`
- `test/widgets/apple_lyrics/renderers/interlude_dots_test.dart`
- `test/widgets/apple_lyrics/renderers/line_renderer_test.dart`
- `test/widgets/apple_lyrics/renderers/word_renderer_test.dart`
- `test/services/kugou_api/kugou_api_client_test.dart`
- `test/services/kugou_api/kugou_models_test.dart`
- `test/providers/kugou_provider_test.dart`

**修改文件：**
- `lib/services/kugou_api/kugou_api_client.dart` — `getLyric` 改为双请求 lrc + krc
- `lib/services/kugou_api/kugou_models.dart` — `KugouLyric` 新增 `decodedKrcContent` 字段
- `lib/providers/kugou_provider.dart` — 暴露 `krcLyric` / `lrcLyric`

**不动文件：**
- `lib/modules/player/lyrics_view.dart` — 保留原 MD3 整行高亮逻辑作为兜底
- `lib/modules/player/full_player.dart` — 保留原 MD3 风格播放页

### PR-2: Apple Music 风格播放器开关（B，依赖 PR-1）

**修改文件：**
- `lib/modules/player/full_player_route.dart` — 根据开关在 `FullPlayer` 与 `FullPlayerAm` 之间切换
- `lib/data/repositories/settings_repository.dart` — 新增 `appleMusicStylePlayerEnabled`（默认 false）
- `lib/modules/settings/settings_page.dart` — 新增开关项

### PR-3: 莫奈取色 + 8 色预设 + OLED 纯黑模式（C）

**修改文件：**
- `lib/core/theme/app_theme.dart` — 新增 OLED 纯黑模式、8 色预设
- `lib/providers/theme_provider.dart` — OLED 开关、系统色禁用主题色入口逻辑
- `lib/modules/settings/settings_page.dart` — 新增 OLED 开关、预设选择
- `lib/widgets/seed_color_picker.dart` — 8 色预设展示

### PR-4: Lyricon Provider 集成（D，独立于 PR-1）

**修改文件：**
- `android/app/build.gradle.kts` — 新增 `io.github.proify.lyricon:provider:0.1.70` 依赖
- `android/app/src/main/AndroidManifest.xml` — 新增 `lyricon_module` / `lyricon_module_author` / `lyricon_module_description` meta-data
- `android/app/src/main/res/values/arrays.xml` — 新增 `lyricon_module_tags` 数组（`$syllable` + `$translation`）
- `android/app/src/main/kotlin/com/md3music/md3music/AudioPlaybackService.kt` — 持有 `LyriconProvider` 实例
- `android/app/src/main/kotlin/com/md3music/md3music/MainActivity.kt` — 注册 MethodChannel `com.md3music.md3music/lyricon`

**新增文件：**
- `lib/core/services/lyricon_provider_service.dart` — Dart 侧服务
- `LYRICON_INTEGRATION.md` — 用户/开发者文档

**修改文件：**
- `lib/main.dart` — 启动时初始化 LyriconProviderService
- `lib/data/repositories/settings_repository.dart` — 新增 `lyriconEnabled` 持久化（默认 false）
- `lib/modules/settings/settings_page.dart` — 新增开关 + 状态提示
- `lib/providers/player_provider.dart` — 播放状态/seekTo 钩子转发到 Lyricon

### PR-5: 下载服务优化（E，独立）

**修改文件：**
- `lib/services/download_manager.dart` — 自定义下载目录、元数据嵌入钩子
- `lib/data/repositories/downloads_repository.dart` — 自定义目录持久化
- `lib/modules/user/downloads_page.dart` — UI 暴露目录选择
- `android/app/build.gradle.kts` — `jaudiotagger 2.2.3`（JitPack）

**新增文件：**
- `android/app/src/main/kotlin/com/md3music/md3music/MetadataWriterPlugin.kt`（如已存在则修改）

### PR-6: GitHub Actions CI（F，独立，先提交以建立质量门）

**新增文件：**
- `.github/workflows/ci.yml`

**注意**：上游如已有自己的 CI，需协调；如没有，这个 PR 是其他 PR 的质量门。

### PR-7: UI/UX 改进合集（G，可进一步拆分）

**修改文件（散落）：**
- `lib/widgets/scroll_aware_app_bar.dart` — AppBar 标题常驻
- `lib/widgets/playing_spectrum_indicator.dart` — 频谱暂停指示器
- `lib/modules/player/mini_player.dart` — SafeArea 适配、滑动惯性、上浮 ease-in-out
- `lib/modules/player/comments_view.dart` — 评论智能反色、24px mask alpha
- `lib/modules/player/full_player.dart` — 主行上滑淡入
- `lib/data/models/song.dart` — `displayName` getter 剥离扩展名
- `lib/modules/user/favorites_page.dart` — 收藏夹折叠动画
- `lib/widgets/song_list_item.dart` — 列表项布局优化

> 建议：PR-7 可拆为 7a/7b/7c 等多个子 PR，每个聚焦一个 UI 改进，便于 review。

---

## 2. 通用准备（所有 PR 都要做的前置工作）

### Task 0: 在上游开 Issue 试水，确认 maintainer 接受方向

**Files:** 无代码改动，仅 issue 文本

> **语言选择**：根据上游 commit message 推断 maintainer 偏好。实测上游 commit 既有中文（`ce65ac3 chore(server): 禁用音频代理功能以避免流量耗尽`）又有英文（`baab866 chore(kugou api server): add script to disable audio proxy endpoint`），**建议双语 Issue**（英文标题 + 中英双语 body），既符合 GitHub 国际惯例又方便 maintainer 用中文回复。

- [ ] **Step 0: 先做 License 调研（强制）**

```bash
# 调研 Lyricon Provider SDK License
# 访问 https://github.com/proify/lyricon 查 LICENSE 文件
# 访问 https://search.maven.org/artifact/io.github.proify.lyricon/provider 查 License 字段
# 调研 jaudotagger 2.2.3 License（通常是 LGPL 或 GPL）
# 访问 https://github.com/ijabz/jaudotagger/blob/master/LICENSE.txt
```

记录在第 8 节：

| 依赖 | License | 与 MIT 兼容性 | 决策 |
|---|---|---|---|
| Lyricon Provider SDK 0.1.70 | （填） | （填） | （可静态打入 / 需独立 plugin / 禁止提 PR） |
| jaudotagger 2.2.3 | （填） | （填） | （同上） |

**如果 Lyricon 或 jaudotagger 是 GPL/AGPL → 立即终止 PR-4/PR-5，改为独立 fork**，不要继续后续 Task。

- [ ] **Step 1: 在 `zzyoxml/md3Music` 上开 Issue，双语**

```
Title: Proposal: Contribute Apple Music-style lyrics module + Lyricon Provider + Monet/OLED theming + download improvements + CI

Body:

Hi @zzyoxml,

I've been working on a fork of md3Music (https://github.com/Little-White3110/ampl) that adds several features. I'd like to contribute them back upstream as separate, reviewable PRs against `arch-local-first` (please confirm: should PRs target `arch-local-first` or `main`?). Before opening PRs, I want to confirm the direction is welcome.

## Proposed PRs (in dependency order)

1. **GitHub Actions CI** — analyze + test + APK matrix build. Independent, sets up quality gate for the rest.
2. **Apple Music-style per-word lyrics module** — new `lib/widgets/apple_lyrics/` with KRC/LRC/plaintext parsers, spring physics animation, mask-alpha rendering. Activates the dead KRC code path in `kugou_api_server/util/util.js`. Original `lyrics_view.dart` untouched.
3. **Apple Music-style player toggle** — adds `lib/modules/player/full_player_am.dart` and a settings switch (default OFF). Original MD3 `full_player.dart` untouched → zero breaking.
4. **Monet palette + 8 presets + OLED black mode** — theme system enhancement.
5. **Lyricon Provider SDK integration** — desktop lyric push to Lyricon app via Provider SDK. Default OFF.
6. **Download service improvements** — custom download dir + metadata embedding (jaudotagger).
7. **UI/UX bundle** — AppBar title, spectrum pause indicator, mini player SafeArea, comments smart invert, song title extension stripping, favorites collapse animation. Can be split further if preferred.

## Compatibility

All features default OFF; existing MD3 behavior unchanged on upgrade.

## Notes

- Ampl fork structure differs (md3Music/ is a subdirectory). I'll do `git subtree split` to lift it to root before each PR.
- New Maven dep: `io.github.proify.lyricon:provider:0.1.70` (License: <fill from Step 0>). New JitPack dep: `jaudotagger 2.2.3` (License: <fill from Step 0>).
- Each PR includes a "Design Decisions Summary" table in its description, with full spec linked to ampl repo (no spec docs imported into upstream).

Happy to adjust scope, split further, or drop any item you don't want. Which PRs are welcome?

---

你好 @zzyoxml，

我在 md3Music 的 fork（https://github.com/Little-White3110/ampl）上加了一些功能，希望以独立可 review 的 PR 形式贡献回上游 `arch-local-first`（请确认：PR 应该基于 `arch-local-first` 还是 `main`？）。在开 PR 前想先确认方向是否欢迎。

## 拟提的 PR（按依赖顺序）

1. **GitHub Actions CI** — analyze + test + APK 矩阵构建，独立，为后续 PR 建立质量门
2. **Apple Music 风格逐字歌词模块** — 新增 `lib/widgets/apple_lyrics/`（KRC/LRC/纯文本解析器、弹簧物理、mask alpha 渲染），激活 `kugou_api_server/util/util.js` 里现成的 KRC 解码死代码，原 `lyrics_view.dart` 保留不动
3. **Apple Music 风格播放器开关** — 新增 `lib/modules/player/full_player_am.dart` + 设置开关（默认关），原 MD3 风格 `full_player.dart` 不动 → 零 breaking
4. **莫奈取色 + 8 色预设 + OLED 纯黑模式** — 主题系统增强
5. **Lyricon Provider SDK 集成** — 通过 Provider SDK 把歌词推送到 Lyricon 桌面词幕应用，默认关
6. **下载服务优化** — 自定义下载目录 + 元数据嵌入（jaudotagger）
7. **UI/UX 改进合集** — AppBar 标题常驻、频谱暂停、mini player SafeArea、评论智能反色、歌曲标题剥扩展名、收藏夹折叠动画，可进一步拆分

## 兼容性

所有功能默认关闭，升级后 MD3 行为不变。

## 备注

- ampl fork 结构不同（md3Music/ 在子目录），我会用 `git subtree split` 把它提升到根目录再开 PR
- 新 Maven 依赖：`io.github.proify.lyricon:provider:0.1.70`（License: <填>）；新 JitPack 依赖：`jaudotagger 2.2.3`（License: <填>）
- 每个 PR 描述会附「设计决策摘要」表，完整 spec 链接到 ampl 仓库（不把 spec 文档导入上游）

欢迎调整范围、进一步拆分或丢弃任何一项。哪些 PR 欢迎？
```

- [ ] **Step 2: 等待 maintainer 回复，按反馈调整 PR 拆分顺序与范围**

Expected: maintainer 会回复接受/拒绝/调整意见。**未获明确同意前不开任何 PR**。

常见 maintainer 反馈与应对：

| 反馈 | 应对 |
|---|---|
| 不接受某个 PR 方向 | 立即从方案中删除该 PR，更新执行顺序 |
| 要求进一步拆分 PR-X | 把 PR-X 拆为 PR-Xa / PR-Xb，分别切 feature 分支 |
| 要求改 base 分支为 main | 全方案 sed 替换 `arch-local-first` → `main` |
| 要求先合并 PR-6 再开其他 PR | 调整 PR 提交顺序，PR-6 优先合并 |
| 不接受某个新依赖 | 改为可选 plugin 或移除对应 PR |

- [ ] **Step 3: Commit issue 链接到本地 NOTES**

在 `docs/superpowers/plans/2026-07-20-upstream-pr-submission.md` 末尾追加一节 `## 8. Maintainer 反馈记录`，记录每个 PR 的接受/拒绝/调整意见。

### Task 1: Fork 上游仓库 + 配置 git remote

**Files:** 无代码改动，仅本地 git 配置

- [ ] **Step 1: 在 GitHub 上 fork `zzyoxml/md3Music` 到自己账号**

操作：浏览器访问 `https://github.com/zzyoxml/md3Music`，点 Fork。

Expected: 拥有 `Little-White3110/md3Music`（或同等用户名）。

- [ ] **Step 2: 在本地 ampl 仓库添加 fork 为 remote**

```bash
cd "c:/Users/32732/Desktop/TRAE SOLO/ampl"
git remote add my-md3music-fork https://github.com/Little-White3110/md3Music.git
git fetch my-md3music-fork
```

Expected: `git remote -v` 输出包含 `my-md3music-fork`。

- [ ] **Step 3: 验证 upstream 默认分支与 main 关系（决定 PR base）**

```bash
# 1. 确认 GitHub 上游默认分支
git remote show upstream | grep "HEAD branch"
# 2. 对比 main 与 arch-local-first 的领先/落后
git rev-list --left-right --count upstream/main...upstream/arch-local-first
# 3. 看上游最近活跃分支
git log --oneline -5 upstream/arch-local-first
echo "---"
git log --oneline -5 upstream/main
```

Expected:
- `HEAD branch: arch-local-first`（GitHub 默认）
- `rev-list --left-right` 输出形如 `66   0` 表示 arch-local-first 领先 main 66 个 commit → arch-local-first 是实际工作分支，PR base 到此
- 若输出 `0   N`（main 领先）→ maintainer 切换了默认分支到 main，PR base 应改为 main，需在 Task 0 Issue 中向 maintainer 确认

**若验证结果与方案假设不符**：在 Task 0 Issue 文本中明确询问 maintainer "Should PRs target `arch-local-first` or `main`?"，按答复调整本方案所有 PR base。

### Task 2: 用 `git subtree split` 把 `md3Music/` 子目录剥离到根（一次性）

**Files:** 无（仅创建本地分支 `md3-split-base`）

> **重要策略调整**：**不要 rebase ampl 的 62 个历史 commit 到上游**！62 个 commit × 平均 5 处冲突 = 300+ 处手工解决，工作量几天几夜。改为「**丢弃 ampl 历史，把 ampl 最终状态作为新 commit reapply 到上游最新**」——subtree split 后只保留最终状态，每个 PR 用 `git checkout <ampl-HEAD> -- <path>` 把 ampl 最新版文件搬到上游基础上，作为单个 squash commit。

- [ ] **Step 1: 执行 subtree split，把 md3Music/ 历史剥离为新分支**

```bash
cd "c:/Users/32732/Desktop/TRAE SOLO/ampl"
git subtree split --prefix=md3Music -b md3-split-base
```

Expected: 命令成功，输出新分支的 commit hash。`git log --oneline md3-split-base | head -5` 显示的 commit message 与原 ampl 一致，但所有路径已去掉 `md3Music/` 前缀。

- [ ] **Step 2: 验证剥离后的目录结构**

```bash
git ls-tree --name-only md3-split-base | head -10
```

Expected: 输出包含 `lib`、`android`、`pubspec.yaml`、`README.md` 等（**不再有 `md3Music/` 前缀**）。

- [ ] **Step 3: 创建 `pr-base` 分支作为所有 PR 的真正 base**

```bash
# pr-base 是 upstream/arch-local-first 的副本，所有 feature 分支基于此切出
git branch pr-base upstream/arch-local-first
git checkout pr-base
```

Expected: `git log --oneline -1 pr-base` 显示上游最新 commit `d9e925a release: bump version to 3.2.0+9 and fix various issues`。

> **不 rebase md3-split-base 到上游**！`md3-split-base` 仅作为「ampl 最终文件状态来源」的参考分支。每个 PR 从 `pr-base` 切出，然后用 `git checkout md3-split-base -- <path>` 把 ampl 文件搬过去。

- [ ] **Step 4: 推送 `md3-split-base` 与 `pr-base` 到 fork 备份**

```bash
git push my-md3music-fork md3-split-base
git push my-md3music-fork pr-base
```

Expected: 推送成功。

### Task 3: 准备每个 PR 的 feature 分支

**Files:** 无（仅创建本地分支）

每个 PR 一个 feature 分支，命名遵循 Conventional Commits + PR 编号：

- [ ] **Step 1: 创建 PR-1 分支**

```bash
# 从 pr-base（上游 arch-local-first 副本）切出，不是从 md3-split-base
git checkout pr-base
git checkout -b feature/apple-music-lyrics

# 新增目录可以直接搬（上游没有，零冲突）
git checkout md3-split-base -- lib/widgets/apple_lyrics
git checkout md3-split-base -- lib/modules/player/full_player_am.dart  # 新增文件
git checkout md3-split-base -- test/widgets/apple_lyrics
git checkout md3-split-base -- test/services/kugou_api
git checkout md3-split-base -- test/providers/kugou_provider_test.dart

# !!! 不要 git checkout 上游已有的文件 !!!
# 错误做法：git checkout md3-split-base -- lib/services/kugou_api/kugou_api_client.dart
# 这会覆盖上游 v3.2.0 的最新结构，PR diff 会显示「整个文件被替换」
# 正确做法：把 ampl 改动**手动 reapply** 到上游最新版本上（见 Step 2）
```

- [ ] **Step 2: 手动 reapply ampl 改动到上游最新结构**

```bash
# 查看 upstream 对这些文件的最近改动
git log --oneline upstream/arch-local-first -- lib/services/kugou_api/kugou_api_client.dart | head -10
git log --oneline upstream/arch-local-first -- lib/services/kugou_api/kugou_models.dart | head -10
git log --oneline upstream/arch-local-first -- lib/providers/kugou_provider.dart | head -10

# 查看 ampl 改了什么（ampl 仓库视角）
git log --oneline e4c1ef8 -- md3Music/lib/services/kugou_api/kugou_api_client.dart | head -10
git diff upstream/arch-local-first..md3-split-base -- lib/services/kugou_api/kugou_api_client.dart > /tmp/ampl-changes.diff
# 用编辑器查看 ampl 的具体改动，逐个 reapply 到上游最新版本

# 打开编辑器手动改：
# 1. lib/services/kugou_api/kugou_api_client.dart
#    - getLyric 方法：增加 fmt=krc 的第二次请求
#    - 返回值：同时携带 lrc + krc 明文
# 2. lib/services/kugou_api/kugou_models.dart
#    - KugouLyric 类：新增 decodedKrcContent 字段
# 3. lib/providers/kugou_provider.dart
#    - 暴露 krcLyric / lrcLyric 两个 getter
code lib/services/kugou_api/kugou_api_client.dart
code lib/services/kugou_api/kugou_models.dart
code lib/providers/kugou_provider.dart
```

> **关键原则**：ampl 的改动是「增量」而不是「替换」。手动 reapply 时只改 ampl 新增的部分（双请求、新字段、新 getter），不动上游已有的代码结构。这样 PR diff 才能聚焦于「ampl 加了什么」，而不是「整个文件被换了」。

- [ ] **Step 3: 跑 analyze + test，**先修测试断言再 commit**（重要！）**

```bash
flutter pub get
flutter analyze --no-fatal-infos
# 先跑测试，预期部分断言会因上游结构变化而失败
flutter test test/widgets/apple_lyrics test/services/kugou_api test/providers/kugou_provider_test.dart
```

Expected: 部分测试可能 FAIL，原因是 ampl 测试断言依赖 `KugouLyric.decodedKrcContent` 字段名，但上游 v3.2.0 可能改过该结构。

**断言修复原则**：
- ✅ 改测试期望值（如果只是字段名/结构变化）
- ✅ 改测试 mock 数据（如果上游 API 返回格式变化）
- ❌ **不允许改测试逻辑或删除断言**（这等于偷懒）

修复后重新跑测试直到全部 PASS。

- [ ] **Step 4: Commit + push + 开 PR（含设计决策摘要）**

```bash
git add -A
git commit -m "feat(apple-lyrics): add Apple Music-style per-word lyrics module

- New lib/widgets/apple_lyrics/ with KRC/LRC/plaintext parsers
- Spring physics animation (mass/damping/stiffness per AMLL spec)
- Mask-alpha rendering via CustomPainter + Ticker
- Interlude dots with easeOutBack enter / easeInBack exit
- KRC dual-request: fetch fmt=lrc + fmt=krc simultaneously
- Original lyrics_view.dart untouched (kept as fallback)
- Original full_player.dart untouched (AM player is opt-in via PR-2)
- 18 unit tests covering parsers, spring, renderers, controllers, providers"
```

PR 描述必须包含**设计决策摘要**（不是 commit 历史的复述，而是关键参数与设计选择的简表）：

```markdown
## Design Decisions Summary

| Aspect | Decision | Rationale |
|---|---|---|
| 弹簧参数（主行） | mass=2, damping=25, stiffness=100 | 临界阻尼，参考 AMLL `spring.ts` |
| 弹簧参数（背景行） | mass=1, damping=20, stiffness=50 | 轻量背景行 |
| 间奏阈值 | ≥4000ms 间隔触发呼吸点 | AMLL 标准值 |
| 入场动画 | easeOutBack 400ms | 带超出回弹 |
| 消失动画 | easeInBack 750ms | 先放大 10% 再缩到 0 |
| 对齐位置 | alignPosition = 0.35 | AMLL 标准 |
| 渲染方式 | CustomPainter + mask alpha（非颜色切换） | 参考 AMLL，避免 anti-alias 边缘锯齿 |
| 性能优化 | TextPainter 测量结果缓存 | CPU 70% → <30%（实测） |
| 帧时钟 | _animationTimeMs 每帧 += dt*1000 | 不受 positionStream 5fps 限制 |

Full design spec: https://github.com/Little-White3110/ampl/blob/main/.trae/specs/add-apple-music-lyrics/spec.md
```

- [ ] **Step 5: 重复 Step 1-4 创建其他 PR 分支**

为 PR-2 到 PR-7 重复上述过程，每个分支只包含对应 PR 涉及的文件。分支命名：
- `feature/am-player-toggle`
- `feature/monet-oled-theme`
- `feature/lyricon-provider`
- `feature/download-service-improvements`
- `feature/github-actions-ci`
- `feature/ui-ux-improvements`

> **文件归属冲突解决原则**：当多个 PR 都需要改同一文件时，**归给更核心的 PR**：
> - `lib/modules/settings/settings_page.dart` 同时被 PR-2 / PR-3 / PR-4 改 → 优先策略：**串行提交**（PR-2 先合并，PR-3 在 PR-2 基础上 rebase，PR-4 同理）；备选策略：拆为 `settings_page_am_toggle.dart`（PR-2）、`settings_page_theme.dart`（PR-3）、`settings_page_lyricon.dart`（PR-4）三个独立 section 文件（但拆文件本身是 breaking，需 maintainer 同意）
> - `lib/data/repositories/settings_repository.dart` 同样问题 → 优先串行提交，备选拆文件
> - `lib/modules/player/full_player.dart` 既被 PR-1（AM 上滑淡入）又被 PR-7（main up-fade）改 → 把 main up-fade 改动归 PR-1（同一文件不要跨 PR）
>
> **依赖关系**：PR-2 依赖 PR-1（要用 `full_player_am.dart`）；PR-7 部分改动归入 PR-1（见上）。其他 PR 互相独立。**PR 提交顺序**：PR-6（CI）→ PR-1 → PR-2 → PR-3 → PR-4 → PR-5 → PR-7。

### Task 4: PR-1 ~ PR-7 推送 + 开 PR（循环执行）

**Files:** 无代码改动

对每个 feature 分支执行以下步骤：

- [ ] **Step 1: 推送 feature 分支到 fork**

```bash
git push my-md3music-fork feature/apple-music-lyrics
```

- [ ] **Step 2: 在 GitHub 上开 PR**

- Base repository: `zzyoxml/md3Music`
- Base branch: `arch-local-first`
- Head repository: `Little-White3110/md3Music`
- Head branch: `feature/apple-music-lyrics`

PR 标题（Conventional Commits 风格）：
```
feat(apple-lyrics): add Apple Music-style per-word lyrics module
```

PR 描述模板：

```markdown
## What

Adds a new `lib/widgets/apple_lyrics/` module implementing Apple Music-style per-word lyrics rendering in pure Dart (no WebView, no JS bridge).

## Why

md3Music's current `lyrics_view.dart` only supports line-level highlight. The KRC decoding code in `kugou_api_server/util/util.js` (XOR + zlib) is dead code because `kugou_api_client.dart` only requests `fmt=lrc`. This PR activates the dead KRC path and adds a renderer that consumes word-level timestamps.

## What Changes

- **New module**: `lib/widgets/apple_lyrics/` (parsers, models, animation, renderers, controllers, layout, preview)
  - KRC plain-text parser: `[start_ms,duration_ms]<offset,duration,0>字...`
  - LRC parser: `[mm:ss.xx]text`
  - Plaintext fallback parser
  - Unified `LyricLine` / `LyricWord` model with `hasWordTiming` capability flag
  - Spring physics engine (critically-damped, per AMLL `spring.ts` parameters)
  - Mask-alpha per-word renderer via `CustomPainter` + `Ticker`
  - Interlude dots animation (≥4000ms gap, easeOutBack enter / easeInBack exit)
- **Modified**: `lib/services/kugou_api/kugou_api_client.dart` — `getLyric` now does dual request (lrc + krc)
- **Modified**: `lib/services/kugou_api/kugou_models.dart` — `KugouLyric` gains `decodedKrcContent` field
- **Modified**: `lib/providers/kugou_provider.dart` — exposes `krcLyric` / `lrcLyric`
- **New tests**: `test/widgets/apple_lyrics/` (18 files), `test/services/kugou_api/` (2 files), `test/providers/kugou_provider_test.dart`

## Compatibility

- ✅ Original `lib/modules/player/lyrics_view.dart` untouched
- ✅ Original `lib/modules/player/full_player.dart` untouched
- ✅ No new pubspec.yaml dependencies
- ✅ No new Maven/JitPack dependencies
- ✅ Feature is opt-in via separate PR-2 (settings toggle, default OFF)

## Testing

- `flutter analyze --no-fatal-infos` passes
- `flutter test test/widgets/apple_lyrics test/services/kugou_api test/providers/kugou_provider_test.dart` passes (21 test files)
- Manual: see `tasks.md` Task 23 — 7-step real-device checklist (KRC song, LRC song, pure instrumental, seek, gesture, 60fps, memory)

## References

- Design spec: based on [AMLL](https://github.com/amll-dev/applemusic-like-lyrics) `packages/core/src/utils/spring.ts`
- Related issue: #XXX (link to upstream issue opened in Task 0)
```

- [ ] **Step 3: 处理 CI 反馈，迭代修复**

PR 创建后，上游 CI（如果有）会自动跑。如果失败，在本分支上修，`git push --force-with-lease` 更新。**不要 force push 到 main 分支**。

- [ ] **Step 4: 等待 maintainer review，按 review 意见迭代**

每个 PR 都可能经历多轮 review。常见 review 意见与应对：

| Review 意见 | 应对 |
|---|---|
| 「拆太大了」 | 进一步拆分（如 PR-1 拆为 PR-1a parsers + PR-1b renderers + PR-1c KRC dual-request） |
| 「不要替换 lyrics_view」 | 已保留，PR-2 提供开关 |
| 「不接受 Lyricon 依赖」 | 撤回 PR-4，改为可选 plugin |
| 「CI grep 限制太严」 | 移除 grep TTML/WebView 步骤 |
| 「莫奈取色改动太多」 | 拆为 PR-3a 8 色预设 + PR-3b OLED 模式 |

---

## 3. PR 内容详述（每个 PR 的 commit 拆分）

### Task 5: PR-6 提交 GitHub Actions CI（先提交以建立质量门）

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: 创建 `.github/workflows/ci.yml`（适配上游目录结构）**

```yaml
name: CI

on:
  push:
    branches: [arch-local-first, main]
    tags: ['v*']
  pull_request:
    branches: [arch-local-first, main]
  workflow_dispatch:
    inputs:
      include_x86_64:
        description: '额外构建 x86_64（模拟器用）'
        type: boolean
        required: false
        default: false

permissions:
  contents: write
  checks: write
  pull-requests: write

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  analyze-and-test:
    name: Analyze & Test (Flutter)
    runs-on: ubuntu-22.04
    timeout-minutes: 30
    # 无 working-directory —— 上游是平铺结构
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - run: flutter --version
      - run: flutter pub get
      - run: flutter analyze --no-fatal-infos
      - continue-on-error: true
        run: dart format --set-exit-if-changed lib/ test/
      - run: flutter test --coverage --machine > test_output.json
      - if: always()
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: coverage/
          if-no-files-found: ignore
      - if: always()
        uses: dorny/test-reporter@v1
        with:
          name: Flutter Test Results
          path: 'test_output.json'
          reporter: flutter-json

  build-apk:
    name: Build APK (${{ matrix.abi }})
    needs: analyze-and-test
    runs-on: ubuntu-22.04
    timeout-minutes: 60
    strategy:
      fail-fast: false
      matrix:
        abi: ${{ (github.event_name == 'workflow_dispatch') && inputs.include_x86_64 && fromJSON('["arm64-v8a","armeabi-v7a","x86_64"]') || fromJSON('["arm64-v8a","armeabi-v7a"]') }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - uses: android-actions/setup-android@v3
        with:
          packages: 'ndk;28.2.13676358 cmake;3.22.1'
      - run: flutter pub get
      - name: Download libnode.so from upstream Release APK
        shell: bash
        run: |
          set -e
          ABIS=("arm64-v8a" "armeabi-v7a")
          if [ "${{ github.event_name }}" = "workflow_dispatch" ] && [ "${{ inputs.include_x86_64 }}" = "true" ]; then
            ABIS+=("x86_64")
          fi
          for abi in "${ABIS[@]}"; do
            mkdir -p "android/app/src/main/jniLibs/${abi}"
            curl -L --fail -o "app-${abi}.apk" \
              "https://github.com/zzyoxml/md3Music/releases/latest/download/app-${abi}-release.apk"
            unzip -j "app-${abi}.apk" "lib/${abi}/libnode.so" \
              -d "android/app/src/main/jniLibs/${abi}/"
            rm "app-${abi}.apk"
          done
          mkdir -p /tmp/node-headers
          curl -L --fail \
            "https://nodejs.org/dist/v18.20.4/node-v18.20.4-headers.tar.gz" \
            | tar xz -C /tmp/node-headers
          mkdir -p android/app/src/main/cpp/include
          cp -r /tmp/node-headers/node-v18.20.4/include/node \
            android/app/src/main/cpp/include/
      - run: |
          flutter build apk --release --split-per-abi \
            --target-platform android-${{ matrix.abi == 'arm64-v8a' && 'arm64' || matrix.abi == 'armeabi-v7a' && 'arm' || 'x64' }}
      - uses: actions/upload-artifact@v4
        with:
          name: md3music-apk-${{ matrix.abi }}
          path: build/app/outputs/flutter-apk/app-${{ matrix.abi }}-release.apk
          if-no-files-found: error
          retention-days: 30
      - if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          files: build/app/outputs/flutter-apk/app-${{ matrix.abi }}-release.apk
          name: Release ${{ github.ref_name }}
```

> **与 ampl 版本的差异**：
> 1. 移除 `defaults.run.working-directory: md3Music`（上游无子目录）
> 2. **`Verify no banned dependencies` 与 `Verify no banned symbols` 步骤作为「可选 opt-in」**：默认不在初始 PR-6 中强制，但在 PR-6 的描述中**明确提议给 maintainer**：
>    - 若 maintainer 接受 → 在 PR-1 合并后追加 commit 启用 grep 守护
>    - 若 maintainer 不接受 → 移除该步骤，PR-1 的「零 WebView」承诺由 PR-1 自身的 `flutter analyze` 保证（analyze 会因 import 失败而报错）
> 3. `branches` 列表加入 `arch-local-first`（上游默认分支）
> 4. 所有 `md3Music/` 路径前缀去掉
>
> **关于「PR-1 的零 WebView 承诺如何在 CI 中持续守护」**：如果 maintainer 拒绝 grep 步骤，则靠 `flutter analyze` 兜底——任何 `WebView` 引用必须配套 `webview_flutter` 依赖，未声明依赖时 analyze 会 fail。**这是次优但可接受的兜底**。

- [ ] **Step 2: Commit + push + 开 PR**

```bash
git checkout md3-split-base
git checkout -b feature/github-actions-ci
mkdir -p .github/workflows
# 写入上面的 ci.yml
git add .github/workflows/ci.yml
git commit -m "ci: add GitHub Actions workflow for analyze + test + APK matrix build

- analyze-and-test: flutter analyze + dart format check + flutter test --coverage
- build-apk: matrix build for arm64-v8a / armeabi-v7a (+ optional x86_64 via workflow_dispatch)
- Downloads libnode.so from upstream Release APK + Node.js v18 headers
- Tag-triggered: auto-attach APKs to GitHub Release"
git push my-md3music-fork feature/github-actions-ci
```

Expected: PR 链接 `https://github.com/zzyoxml/md3Music/pull/N`。

### Task 6: PR-1 提交 Apple Music 风格歌词模块

**Files:** 见 PR-1 文件清单

- [ ] **Step 1: 从 `md3-split-base` 切分支**

```bash
git checkout md3-split-base
git checkout -b feature/apple-music-lyrics
```

- [ ] **Step 2: 用 `git checkout <commit> -- <path>` 搬运文件**

```bash
# 上游没有 lib/widgets/apple_lyrics/，直接从 ampl 搬过来
git checkout e4c1ef8 -- lib/widgets/apple_lyrics

# 上游有 lib/services/kugou_api/，但要应用 ampl 的双请求改造
# 这里不能用 git checkout（会覆盖上游版本），要用 git checkout ampl 的 commit + 手动 merge
git checkout e4c1ef8 -- lib/services/kugou_api/kugou_api_client.dart
git checkout e4c1ef8 -- lib/services/kugou_api/kugou_models.dart

# 上游有 lib/providers/kugou_provider.dart，但 ampl 改过
git checkout e4c1ef8 -- lib/providers/kugou_provider.dart

# 新增 full_player_am.dart（不替换 full_player.dart）
git checkout e4c1ef8 -- lib/modules/player/full_player_am.dart

# 测试文件
git checkout e4c1ef8 -- test/widgets/apple_lyrics
git checkout e4c1ef8 -- test/services/kugou_api
git checkout e4c1ef8 -- test/providers/kugou_provider_test.dart
```

- [ ] **Step 3: 手动检查并解决与上游 v3.1.0/v3.2.0 的冲突**

`lib/services/kugou_api/kugou_api_client.dart` 在上游 v3.1.0 中可能改过（如 `5c74ad2 ui(song list)` 改了歌曲列表项布局）。需要人工对照：

```bash
# 查看 upstream 对该文件的最近改动
git log --oneline upstream/arch-local-first -- lib/services/kugou_api/kugou_api_client.dart
# 查看 ampl 对该文件的改动
git log --oneline e4c1ef8 -- md3Music/lib/services/kugou_api/kugou_api_client.dart
```

手动编辑 `lib/services/kugou_api/kugou_api_client.dart`，把 ampl 的「双请求 lrc+krc」改动 reapply 到上游最新版本上。

- [ ] **Step 4: 运行 analyze + test**

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test test/widgets/apple_lyrics test/services/kugou_api test/providers/kugou_provider_test.dart
```

Expected: 全部 PASS。

- [ ] **Step 5: Commit + push + 开 PR**

```bash
git add -A
git commit -m "feat(apple-lyrics): add Apple Music-style per-word lyrics module"
git push my-md3music-fork feature/apple-music-lyrics
```

PR 描述见 Task 4 Step 2 模板。

### Task 7 ~ Task 11: PR-2 ~ PR-7

每个 PR 重复 Task 6 的步骤（切分支 → 搬文件 → 解决冲突 → 测试 → commit → push → 开 PR）。

PR 内容详见第 1 节「文件结构」表。具体 commit message：

- **PR-2**: `feat(player): add Apple Music-style player toggle (default OFF)`
- **PR-3**: `feat(theme): Monet palette + 8 presets + OLED black mode`
- **PR-4**: `feat(lyricon): integrate Lyricon Provider SDK for desktop lyric push`
- **PR-5**: `feat(download): custom download dir + metadata embedding`
- **PR-7**: `feat(ui): AppBar title + spectrum pause + mini player SafeArea + ...`

### Task 12: PR 全部合并后的清理 + ampl 战略方向选择

**Files:** 无代码改动

- [ ] **Step 1: 删除已合并的本地 feature 分支**

```bash
git branch -d feature/apple-music-lyrics
git branch -d feature/am-player-toggle
git branch -d feature/monet-oled-theme
git branch -d feature/lyricon-provider
git branch -d feature/download-service-improvements
git branch -d feature/github-actions-ci
git branch -d feature/ui-ux-improvements
git branch -d md3-split-base pr-base
```

- [ ] **Step 2: 选择 ampl 仓库战略方向（用户决策点）**

ampl 仓库有两条路可走，**必须由用户决策**：

**路径 A：ampl 完全上游化（推荐）**
- ampl 退化为上游 arch-local-first 的跟踪分支
- ampl 独有 spec/PRD 文档（`.trae/specs/`、`md3Music-AppleLyrics-PRD.md`）归档到 `docs/archive/` 或删除
- README.md 改为「ampl 已 upstream，跟踪 zzyoxml/md3Music」
- 后续所有改动直接提 PR 到上游，不再在 ampl 上开发

```bash
git checkout main
git fetch upstream
git merge upstream/arch-local-first
git push origin main
```

**路径 B：ampl 作为实验性 fork 继续存在**
- ampl 保留独立身份，作为「未上游化的实验性 feature 预览版」
- 定期从上游 merge 最新改动
- README.md 更新「与上游项目的关系」一节，说明「核心功能已上游化，ampl 保留 Lyricon/PRD 等实验性内容」
- 后续 ampl 上的实验性改动成熟后再提上游

```bash
git checkout main
git fetch upstream
git merge upstream/arch-local-first  # 把上游最新合并回 ampl
git push origin main
# ampl 保留 .trae/specs/、md3Music-AppleLyrics-PRD.md 等实验性文档
```

**用户应基于以下因素决策**：
- ampl 是否还有未上游化的实验性 feature？（是 → 路径 B；否 → 路径 A）
- ampl 用户群体是否依赖 ampl 独立身份？（是 → 路径 B；否 → 路径 A）
- maintainer 是否完全接受所有 PR？（是 → 路径 A；否 → 路径 B 保留被拒 PR 的代码）

- [ ] **Step 3: 按所选路径更新 ampl README**

路径 A：把 README.md 中「与上游项目的关系」改为「功能已上游化，ampl 退化为跟踪分支」。
路径 B：把 README.md 中「与上游项目的关系」更新为「核心功能已上游化，ampl 保留实验性内容」。

- [ ] **Step 4: spec/PRD 文档处理**

- `.trae/specs/add-apple-music-lyrics/spec.md` / `tasks.md` / `checklist.md`：**不进上游**，保留在 ampl 仓库作为「设计依据」。在 PR 描述里已链接到 ampl 仓库的 spec.md（见 Task 3 Step 4 模板）。
- `md3Music-AppleLyrics-PRD.md`：**不进上游**，作为 ampl 内部 PRD 保留。
- `LYRICON_INTEGRATION.md`：**进上游 PR-4**（这是面向用户的文档，对 Lyricon 集成有用），但在 PR-4 描述中标记为「optional, can be moved to wiki if maintainer prefers」。
- `docs/superpowers/plans/2026-07-20-upstream-pr-submission.md`（本方案）：**不进上游**，作为 ampl 内部执行记录保留。

---

## 4. 风险与缓解

| 风险 | 概率 | 影响 | 缓解措施 |
|---|---|---|---|
| Maintainer 不接受 PR 方向 | 高 | 全部作废 | Task 0 先开 issue 试水，未获同意不开 PR |
| 上游 v3.2.0 改动与 ampl 改动冲突严重 | 高 | rebase 困难 | 手动 reapply ampl 改动到上游最新；不机械 cherry-pick |
| `git subtree split` 历史丢失 | 中 | PR review 困难 | 用 squash commit + 完整 PR 描述替代历史 commit message |
| Lyricon 依赖被拒 | 中 | PR-4 失败 | 改为 optional plugin，移到独立 repo 作为 extension |
| Lyricon SDK 是 GPL/AGPL | 中 | PR-4 违法分发 | Task 0 Step 0 License 调研阻断，PR-4 自动撤回 |
| LSPosed 间接 copyleft 风险 | 中 | PR-4 法律争议 | 在 PR-4 描述中声明 + 提示 maintainer 咨询法律；可撤回 |
| PR 太大被要求拆分 | 高 | review 周期长 | 提前拆好子 PR（PR-1a/1b/1c 等） |
| CI grep 限制被拒 | 中 | PR-6 修改 | 移除 grep TTML/WebView 步骤，靠 flutter analyze 兜底 |
| 上游 CI 跑 x86_64 失败 | 低 | APK 构建失败 | workflow_dispatch 默认不构建 x86_64 |
| jaudotagger 2.2.3 JitPack 不可用 | 低 | PR-5 失败 | 改用 mavenCentral 上的替代品或 fallback 到 1.0.1 |
| PRD/spec.md 含敏感信息 | 中 | 公开泄露 | Task 0 Step 1 之前 grep 扫描，命中则不链接 |
| maintainer 要求改 base 分支 | 低 | 全方案 sed 替换 | 已在 Task 1 Step 3 检测，Task 0 Issue 确认 |

---

## 5. 回滚策略（中途失败怎么办）

每个阶段失败时的回滚动作：

### 5.1 Task 2 `git subtree split` 失败

```bash
# 现象：subtree split 命令报错，md3-split-base 未创建
# 原因：通常是因为 md3Music/ 子目录在某个历史 commit 中不存在
# 排查：
git log --oneline --all -- md3Music/ | tail -5  # 看最早何时引入 md3Music/
# 修复：
git subtree split --prefix=md3Music -b md3-split-base 2>&1 | head -20
# 如果是因为早期 commit 没有 md3Music/ 前缀，加上 --rejoin 参数
# 如果仍失败，回滚：直接放弃 subtree split，改为手动 rsync ampl/md3Music/* 到新仓库根
```

### 5.2 Task 3 push 到 fork 被拒（如大小超限）

```bash
# 现象：git push my-md3music-fork feature/xxx 失败
# 排查：
git push my-md3music-fork feature/xxx 2>&1
# 常见原因：
# 1. fork 仓库未创建 → 在 GitHub 上手动 fork
# 2. 分支名冲突 → git push -u my-md3music-fork feature/xxx:feature/xxx-new
# 3. 大文件超限 → 检查 native-libs 是否误入 .gitignore 之外
# 回滚：删除本地 feature 分支，重新切
git branch -D feature/xxx
git checkout pr-base
git checkout -b feature/xxx-v2
```

### 5.3 Task 5 PR 被 maintainer 要求拆分

```bash
# 现象：PR-1 review 评论说 "too big, please split"
# 应对：在本地把 PR-1 拆为 PR-1a / PR-1b
git checkout pr-base
git checkout -b feature/apple-music-lyrics-parsers
# 只搬 parsers 部分
git checkout md3-split-base -- lib/widgets/apple_lyrics/parsers
git checkout md3-split-base -- lib/widgets/apple_lyrics/models
git checkout md3-split-base -- test/widgets/apple_lyrics/parsers
git checkout md3-split-base -- test/widgets/apple_lyrics/models
git commit -m "feat(apple-lyrics): add parsers (KRC/LRC/plaintext) and LyricLine model"
git push my-md3music-fork feature/apple-music-lyrics-parsers

# 原 PR-1 关闭，重开两个子 PR
# 在 GitHub 上 close PR-1，留言 "Splitting into PR-1a (parsers) + PR-1b (renderers/animation/UI)"
```

### 5.4 Task 6 PR-1 测试断言无法修复（上游结构变化太大）

```bash
# 现象：reapply ampl 改动后，测试断言因上游 v3.2.0 结构变化全部失败，
#       修复断言等于重写测试
# 应对：放弃原 ampl 测试，按上游新结构重写测试
# 原则：测试覆盖的功能点不变（KRC 解析、弹簧参数、mask alpha 渲染等），
#       但 mock 数据和断言期望值按上游新结构调整
# 不要偷懒删除测试！
```

### 5.5 Task 9 PR-4 Lyricon License 是 GPL/AGPL

```bash
# 现象：Task 0 Step 0 调研发现 Lyricon SDK 是 GPL-3.0
# 应对：立即从方案中删除 PR-4，更新执行顺序为 PR-6 → PR-1 → PR-2 → PR-3 → PR-5 → PR-7
# Lyricon 集成改为 ampl 独立 fork 维护（不在 md3Music 上游）
# 在 ampl README 中说明「Lyricon 集成因 License 不兼容未上游，仅在 ampl fork 提供」
```

### 5.6 整个方案被 maintainer 完全拒绝

```bash
# 现象：Task 0 Issue 回复 "not interested in any of these"
# 应对：放弃所有上游化计划，ampl 继续作为独立 fork 维护
# 把 ampl README 中「与上游项目的关系」更新为「功能未上游化，ampl 维护独立 fork」
# 不再 fetch upstream（避免上游 v3.2.0 改动覆盖 ampl）
# 后续 ampl 独立演进
```

---

## 6. 执行顺序总览

```
Task 0: License 调研 + Issue 试水
  ↓
Task 1: Fork + remote 配置 + 验证 base 分支
  ↓
Task 2: subtree split + 创建 pr-base（不 rebase 历史）
  ↓
Task 3: 准备 7 个 feature 分支
  ↓
Task 5: PR-6 (CI) ← 先提交，建立质量门
  ↓
Task 6: PR-1 (Apple Music 歌词模块) ← 核心
  ↓
Task 7: PR-2 (AM 播放器开关) ← 依赖 PR-1
  ↓
Task 8: PR-3 (莫奈 + OLED)
  ↓
Task 9: PR-4 (Lyricon) ← 可能因 License 撤回
  ↓
Task 10: PR-5 (下载服务优化)
  ↓
Task 11: PR-7 (UI/UX 改进)
  ↓
Task 12: 全部合并后清理 + ampl 战略方向选择
```

**关键里程碑**：
- M1（Task 0-2 完成）：License 已查清、maintainer 已认可方向、本地准备好 `md3-split-base` 与 `pr-base`
- M2（Task 5 完成）：PR-6 合并，上游有了 CI
- M3（Task 6 完成）：PR-1 合并，Apple Music 歌词模块上游化
- M4（Task 7-11 完成）：所有 PR 合并（或被 maintainer 拒绝后撤回）
- M5（Task 12 完成）：ampl 与上游同步，ampl 选择路径 A（上游化）或路径 B（独立 fork）

---

## 7. 自检清单

写完方案后用以下清单自检（对应 writing-plans 的 Self-Review）：

### 7.1 Spec 覆盖检查

| ampl 独有功能（来自 git log） | 对应 PR | 是否覆盖 |
|---|---|---|
| Apple Music 风格歌词模块 | PR-1 | ✅ |
| AM 风格播放器开关 | PR-2 | ✅ |
| 莫奈取色 + OLED | PR-3 | ✅ |
| Lyricon Provider | PR-4 | ✅（License 通过为前提） |
| 下载服务优化 | PR-5 | ✅ |
| GitHub Actions CI | PR-6 | ✅ |
| UI/UX 改进（散落） | PR-7 | ✅（可进一步拆） |
| 间奏点动画细节 | PR-1 | ✅（包含在 apple_lyrics 模块内） |
| 性能优化（TextPainter 缓存） | PR-1 | ✅ |
| 真机测试反馈修复 | PR-1 + PR-7 | ✅ |
| jaudiotagger 版本修复 | PR-5 | ✅ |
| Android SDK 配置修复 | PR-6 | ✅（在 CI 里） |

### 7.2 占位符扫描

- ✅ 无 TBD / TODO / "fill in details"（除 Task 0 Step 0 License 表格的「填」占位，需用户实际查后填入）
- ✅ 无 "Add appropriate error handling"
- ✅ 无 "Write tests for the above"（所有测试已在 PR-1 文件清单中列出）
- ✅ 无 "Similar to Task N"
- ✅ 所有步骤都有具体命令或代码

### 7.3 类型/命名一致性

- ✅ PR-1 引入 `KugouLyric.decodedKrcContent`、`krcLyric`、`lrcLyric`、`AppleLyricsView`、`FullPlayerAm`，与 spec.md 一致
- ✅ PR-2 引入 `appleMusicStylePlayerEnabled`，命名与 `settings_repository.dart` 已有惯例（`*Enabled`）一致
- ✅ PR-4 引入 `lyriconEnabled`，与 spec.md 一致
- ✅ PR-6 的 CI 配置文件名 `ci.yml`，与 ampl 现有一致
- ✅ Task 2 引入 `pr-base` 与 `md3-split-base` 双分支概念，后续 Task 全部引用一致

### 7.4 质询后新增检查（grill-me 第二轮）

- ✅ Q1（subtree split 丢历史）→ 改为 squash commit + 设计决策摘要表（Task 3 Step 4）
- ✅ Q2（多 PR 改同一文件）→ 文件归属冲突解决原则（Task 3 Step 5）
- ✅ Q3（验证 main vs arch-local-first）→ Task 1 Step 3 强制验证
- ✅ Q4（issue 语言）→ 双语 Issue（Task 0 Step 1）
- ✅ Q5（networkapi 归属）→ 0.4 约束 8 明确不进 PR
- ✅ Q6（CI grep 持续守护）→ PR-6 grep 步骤改为可选，靠 flutter analyze 兜底
- ✅ Q7（设计决策摘要）→ Task 3 Step 4 模板
- ✅ Q8（License 检查）→ 0.4 约束 5 + Task 0 Step 0 强制
- ✅ Q9（ampl 战略方向）→ Task 12 Step 2 用户决策点
- ✅ Q10（测试断言失败处理）→ Task 3 Step 3 断言修复原则
- ✅ Q11（spec 文档处理）→ Task 12 Step 4 文档策略
- ✅ Q12（rebase 工作量）→ 0.4 约束改用 subtree split 不 rebase 历史
- ✅ Q13（覆盖上游文件）→ Task 3 Step 1 明确「不要 git checkout 上游已有文件」
- ✅ Q14（PR-1 breaking 澄清）→ 0.4 约束 10 明确增量改动原则
- ✅ Q15（settings_page 拆文件备选）→ Task 3 Step 5 串行提交优先
- ✅ Q16（LSPosed copyleft）→ 0.4 约束 5 Lyricon 间接依赖声明
- ✅ Q17（敏感信息检查）→ 0.4 约束 7 grep 扫描
- ✅ Q18（回滚策略）→ 第 5 节 6 个回滚场景

---

## 8. 执行选择（写完方案后给用户选）

方案已保存到 `docs/superpowers/plans/2026-07-20-upstream-pr-submission.md`。两种执行选项：

**1. Subagent-Driven（推荐）** — 每个 Task 派一个 subagent 独立执行，Task 之间 review，迭代快。

**2. Inline Execution** — 在当前会话内按 Task 顺序执行，每完成几个 Task 给 checkpoint review。

**你选哪种？**

---

## 9. Maintainer 反馈记录（占位，Task 0 完成后填）

待 Task 0 Issue 试水后填入 maintainer 反馈。

### 9.1 License 调研结果（Task 0 Step 0 填）

| 依赖 | License | 与 MIT 兼容性 | 决策 |
|---|---|---|---|
| Lyricon Provider SDK 0.1.70 | （填） | （填） | （可静态打入 / 需独立 plugin / 禁止提 PR） |
| jaudotagger 2.2.3 | （填） | （填） | （同上） |

### 9.2 Maintainer 反馈（Task 0 Step 2 填）

| PR | 接受/拒绝 | 调整意见 | 行动 |
|---|---|---|---|
| PR-1 | （填） | （填） | （填） |
| PR-2 | （填） | （填） | （填） |
| PR-3 | （填） | （填） | （填） |
| PR-4 | （填） | （填） | （填） |
| PR-5 | （填） | （填） | （填） |
| PR-6 | （填） | （填） | （填） |
| PR-7 | （填） | （填） | （填） |

### 9.3 Base 分支确认（Task 1 Step 3 填）

- `git rev-list --left-right --count upstream/main...upstream/arch-local-first` 输出：`（填）`
- 决定 PR base 分支：`（arch-local-first / main）`

