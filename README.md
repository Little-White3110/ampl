# ampl — Apple Music 风格逐字歌词集成

<div align="center">

[![Flutter](https://img.shields.io/badge/Flutter-3.12+-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android-green)]()
[![CI](https://github.com/Little-White3110/ampl/actions/workflows/ci.yml/badge.svg)](https://github.com/Little-White3110/ampl/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-MIT-yellow)](md3Music/LICENSE)

</div>

> 在 md3Music（直连酷狗音乐 API 的 Flutter 播放器）基础上，**1:1 复刻 Apple Music 播放页**，参照 [AMLL](https://github.com/amll-dev/applemusic-like-lyrics) 的设计规范用 Dart 原生重写一套逐字歌词模块。

---

## 目录

- [项目简介](#项目简介)
- [功能特性](#功能特性)
- [与上游项目的关系](#与上游项目的关系)
- [仓库结构](#仓库结构)
- [快速开始](#快速开始)
- [GitHub Actions 自动化](#github-actions-自动化)
- [手动验证清单](#手动验证清单)
- [技术栈](#技术栈)
- [致谢](#致谢)
- [许可证](#许可证)

---

## 项目简介

整个 GitHub 生态中，**没有任何一个项目**能同时满足「酷狗音源 + Apple Music 风格 UI + 逐字歌词 + Android」这四个需求。本项目以 [md3Music](https://github.com/zzyoxml/md3Music) 为基础（保留其酷狗音源、嵌入式 Node.js 服务器、下载管理、用户中心等完整功能），参照 [AMLL](https://github.com/amll-dev/applemusic-like-lyrics) 的设计规范用 Dart 原生重写一套 Apple Music 风格逐字歌词模块，并将整个播放页重构为 Apple Music 沉浸式布局。

**本期范围**：仅 Android 端；Windows / Web 端不在范围内。

**核心思路**：
- 不引入 WebView / JS Bridge，零跨进程通信开销
- 不引入 TTML 解析（无数据源），仅支持酷狗 KRC + 标准 LRC + 纯文本
- 解析器链自动检测格式，渲染层只认统一模型 `LyricLine`
- 模型自带 `hasWordTiming` 标记，渲染层据此自动切换逐字/整行模式

---

## 功能特性

### 🎵 歌词渲染（Apple Music 风格）

- **逐字 mask alpha 渲染**：白色文字 + alpha 渐变区分已播/未播（非颜色切换，参考 AMLL）
- **临界阻尼弹簧物理动画**：主行缩放 `mass=2, damping=25, stiffness=100`，背景行 `mass=1, damping=20, stiffness=50`
- **强调辉光（emphasize）**：长字（≥1000ms）触发辉光与缩放，末尾字加强 `amount *= 1.6, blur *= 1.5`
- **间奏点动画**：相邻行间隔 ≥4000ms 时显示呼吸点，提前 250ms 结束准备下一行
- **整行降级模式**：无逐字数据时整行渐入渐出，当前行高亮，非当前行透明度 0.2
- **滚动控制器**：对齐位置 `alignPosition = 0.35`，普通播放动态 stiffness，seeking 模式 `stiffness=90, damping=15`
- **行缩放**：当前行 `scale=1.0`，非当前行 `scale=0.97`，弹簧驱动平滑过渡
- **点击跳转**：点击非当前行调用 `onSeek(line.startTime)`，自动 5000ms 后回弹

### 📱 播放页 1:1 复刻

- **模糊封面背景层**：`ImageFiltered` + `ImageFilter.blur`，sigmaX/Y=50
- **半透明黑蒙版**：`Color(0x59000000)` 叠加
- **上滑展开 / 下拉收起手势**：弹簧驱动切换迷你条 ↔ 全屏页
- **控制栏重做**：上一首/播放暂停/下一首/进度条/时间，全屏页与迷你条两套样式
- **歌词页独立主题**：固定白色文字，不读 MD3 主题色，双主题并存

### 🎧 沿用 md3Music 现有能力

- 酷狗音乐音源（嵌入式 Node.js 服务器直连）
- 多音质（128k / 320k / FLAC）、VIP 自动签到
- 播放历史、收藏、下载管理、桌面歌词
- Material Design 3 主题系统（仅歌词页不受影响）

---

## 与上游项目的关系

| 项目 | 关系 | 说明 |
|------|------|------|
| [md3Music](https://github.com/zzyoxml/md3Music) | **直接 clone 主干自用** | 本仓库 `md3Music/` 子目录为该仓库主干快照，未作为 submodule 引入，方便直接修改 |
| [AMLL](https://github.com/amll-dev/applemusic-like-lyrics) | **仅作设计参考** | 其 `packages/core/src/utils/spring.ts` 弹簧求解器、`lyric-player/dom/` 渲染逻辑、mask alpha 等参数均被 Dart 端等价实现 |
| [KuGouMusicApi](https://github.com/MakcRe/KuGouMusicApi) | md3Music 上游依赖 | 通过其 `fmt=krc` 参数返回的 KRC 数据被本项目双请求策略激活（之前是死代码） |

> **注意**：AMLL 是 Web 技术栈（DOM/React/Vue）的歌词渲染组件库，不能直接用于 Flutter。本项目的 Dart 实现参考其设计但完全重写。

---

## 仓库结构

```
ampl/
├── .github/
│   └── workflows/
│       └── ci.yml                     # CI：analyze + test + APK 构建
├── .trae/
│   └── specs/
│       └── add-apple-music-lyrics/    # Spec-driven 文档
│           ├── spec.md                # 详细规范（含 PRD 修正与 AMLL 参数速查）
│           ├── tasks.md               # 23 项任务拆解
│           └── checklist.md           # 91 项验证清单
├── md3Music/                          # md3Music 仓库主干快照（非 submodule）
│   ├── lib/
│   │   ├── widgets/
│   │   │   └── apple_lyrics/          # 🆕 Apple Music 风格歌词模块
│   │   │       ├── models/            # LyricLine / LyricWord 统一模型
│   │   │       ├── parsers/           # KRC / LRC / 纯文本 / 解析器链
│   │   │       ├── animation/         # 临界阻尼弹簧求解器
│   │   │       ├── renderers/         # 逐字 mask / 强调辉光 / 间奏点 / 整行降级
│   │   │       ├── controllers/       # 滚动控制器 + 行缩放控制器
│   │   │       ├── layout/            # 布局常量集中定义
│   │   │       ├── preview/           # 独立预览页（不依赖播放器）
│   │   │       └── apple_lyrics_view.dart  # 主组件
│   │   ├── modules/player/full_player.dart  # 🔧 重构为 Apple Music 风格播放页
│   │   ├── services/kugou_api/              # 🔧 双请求 LRC+KRC，三級降级
│   │   └── providers/kugou_provider.dart    # 🔧 暴露 krcLyric / lrcLyric
│   ├── test/widgets/apple_lyrics/     # 单元测试（覆盖解析器、弹簧、渲染、控制器）
│   ├── kugou_api_server/              # 嵌入式 Node.js 服务器源码
│   └── ...                            # md3Music 其余原貌
└── md3Music-AppleLyrics-PRD.md        # 原始需求文档
```

---

## 快速开始

### 前置要求

- **Flutter SDK** 3.12.0 或更高版本
- **JDK** 17
- **Android NDK** 28.2.13676358
- **Android CMake** 3.22.1
- **Node.js** 18+（仅在修改 `kugou_api_server/` 时需要）

### 本地运行

```bash
# 1. 克隆本仓库
git clone https://github.com/Little-White3110/ampl.git
cd ampl/md3Music

# 2. 下载 nodejs-mobile Native 库（必需，未入库）
# Windows
.\setup_native.bat
# macOS / Linux
curl -L -o native-libs.zip "https://github.com/zzyoxml/md3Music/releases/latest/download/native-libs.zip"
unzip native-libs.zip && rm native-libs.zip

# 3. 安装 Flutter 依赖
flutter pub get

# 4. 运行（连接 Android 设备后）
flutter run

# 5. 本地单元测试
flutter test

# 6. 本地静态分析
flutter analyze

# 7. 构建 Release APK（分拆 ABI）
flutter build apk --release --split-per-abi
```

### 预览歌词效果（不启动播放器）

在 md3Music App 内：**设置页 → 长按标题 → 歌词预览页**
- 可粘贴 KRC/LRC 原文
- 可拖动时间滑块模拟播放进度
- 不依赖 `just_audio` 与 `KugouProvider`

---

## GitHub Actions 自动化

本仓库 `.github/workflows/ci.yml` 在 **push 到 main**、**Pull Request**、**打 tag（v*）** 时自动触发，包含三个 Job：

### Job 1：`analyze-and-test`（自动化，无需人工介入）

| 步骤 | 内容 |
|------|------|
| `flutter pub get` | 安装依赖 |
| 禁用依赖检查 | grep `pubspec.yaml` 是否引入 `xml` / `webview_flutter` / `flutter_inappwebview` |
| 禁用符号检查 | grep `lib/` 是否出现 `TTML` / `WebView` / `package:xml` |
| `flutter analyze` | 静态分析（语法、类型、lint） |
| `dart format --set-exit-if-changed` | 格式检查（仅报告，不阻断） |
| `flutter test --coverage` | 全量单元测试（覆盖解析器、弹簧、渲染器、控制器、Provider） |
| Coverage 上传 | 作为 artifact 上传 `coverage/` |
| 测试报告 | 用 `dorny/test-reporter` 把 JUnit XML 渲染到 PR Check |

### Job 2：`build-apk`（自动化，矩阵构建 3 ABI）

矩阵：`arm64-v8a` / `armeabi-v7a` / `x86_64`

| 步骤 | 内容 |
|------|------|
| 下载 native-libs.zip | 从 md3Music 上游 Release 拉取 `libnode.so` |
| `flutter build apk --release --split-per-abi` | 构建 Release APK |
| 上传 Artifact | 每个 ABI 一个 artifact，保留 30 天 |
| Release 附件（tag 触发时） | 自动附加到 GitHub Release |

### Job 3：`bundle-apks`（自动化）

把 3 个 ABI 的 APK 打包成 `md3music-all-apks.zip` 一次性下载。

### 触发方式

- `push: branches: [main]` — 主干推送自动跑全部 Job
- `pull_request: branches: [main]` — PR 仅跑 analyze-and-test
- `push: tags: ['v*']` — 打 tag 时额外创建 Release 并附加 APK
- `workflow_dispatch` — 在 Actions 页面手动触发

---

## 手动验证清单

> 以下 7 项**无法在 GitHub Actions 中完成**，需在真机或模拟器上手动运行 App 验证（对应 `tasks.md` 的 Task 23）：

- [ ] **23.1** 播放有 KRC 的歌曲（如「運命の華」hash=`0DC65949D510244B1ADE85A97602649C`），逐字动画正常
- [ ] **23.2** 播放仅有 LRC 的歌曲，整行降级模式正常
- [ ] **23.3** 播放纯音乐（无歌词），占位文本显示
- [ ] **23.4** 验证点击跳转、自动滚动、间奏点均正常
- [ ] **23.5** 验证上滑展开/下拉收起、模糊封面背景、控制栏样式正常
- [ ] **23.6** Flutter DevTools Performance 面板显示 60fps 稳定
- [ ] **23.7** Flutter DevTools Memory 面板显示内存增量 < 5MB

**操作步骤**：
```bash
# 1. 从 GitHub Actions 下载 APK artifact
# 2. adb install md3music-arm64-v8a-release.apk
# 3. 进入 App，按上述清单逐项验证
# 4. 性能 / 内存检查需用 Flutter DevTools（flutter attach）
```

---

## 技术栈

| 类别 | 技术 |
|------|------|
| UI 框架 | Flutter 3.12+ |
| 状态管理 | Provider |
| 音频播放 | just_audio |
| 网络请求 | Dio |
| 嵌入式服务器 | nodejs-mobile (Node.js 18) + esbuild |
| 歌词物理动画 | 自研临界阻尼弹簧求解器（参考 AMLL `spring.ts`） |
| 歌词渲染 | CustomPainter + Ticker（mask alpha 渐变） |
| 歌词格式 | KRC（酷狗逐字，base64+XOR+zlib） / LRC / 纯文本 |
| CI | GitHub Actions（subosito/flutter-action + setup-android） |

---

## 致谢

- [md3Music](https://github.com/zzyoxml/md3Music) — 主项目，集成目标与音源基础
- [AMLL](https://github.com/amll-dev/applemusic-like-lyrics) — 逐字歌词动画效果参考，弹簧参数与 mask alpha 设计来源
- [KuGouMusicApi](https://github.com/MakcRe/KuGouMusicApi) — 酷狗 API 代理参考
- [nodejs-mobile](https://github.com/janeasystems/nodejs-mobile) — 嵌入式 Node.js 框架

---

## 许可证

本项目继承 md3Music 的 [MIT License](md3Music/LICENSE)。
