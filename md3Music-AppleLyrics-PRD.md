# md3Music Apple Music 风格歌词集成 — 开发需求文档

> 版本：v1.3  
> 日期：2026-07-18  
> 状态：需求定义阶段  
> 变更：v1.1 范围收窄为 Android 端；v1.2 更新 AMLL 仓库地址；v1.3 移除已归档的 Cider 参考，AMLL 已覆盖歌词效果参考需求

---

## 一、项目背景

经过对 GitHub 开源音乐播放器的全面调研，发现以下事实：

1. **md3Music**（[zzyoxml/md3Music](https://github.com/zzyoxml/md3Music)）是目前唯一 **直连酷狗音乐 API** 且 **原生支持 Android** 的开源音乐播放器。基于 Flutter 开发，内置嵌入式 Node.js 服务器处理酷狗 API 请求，支持多音质、VIP 自动签到、歌词同步、桌面歌词等功能，MIT 协议。**仓库未归档，活跃维护中**（最新版本 v3.2.0，最后提交 2026-07-08，90 次提交，7 个 Release）。

2. 整个 GitHub 生态中，**没有任何一个项目**能同时满足"酷狗音源 + Apple Music 风格 UI + 逐字歌词 + Android"这四个需求。

3. **AMLL**（[amll-dev/applemusic-like-lyrics](https://github.com/amll-dev/applemusic-like-lyrics)）是 Web 技术栈下完美复刻 Apple Music 逐字歌词动画的**组件库**（DOM/React/Vue 绑定），支持 TTML/YRC/QRC/Lyricify Syllable 等多种歌词格式解析。**注意：AMLL 是歌词渲染组件，不是完整的音乐播放器**——它不处理音频播放、不连接任何音乐 API、不提供歌单管理等功能，也不能作为 Flutter 原生组件直接使用。如果需要完整的 Android 音乐播放器，仍然需要 md3Music 作为主体，AMLL 仅作为歌词渲染效果的设计参考。

综合以上调研结论，**最优路径**是：以 md3Music 的 Android 端为基础，参照 AMLL 的设计规范和动画效果，用 Dart 原生重写一套 Apple Music 风格逐字歌词模块，集成到 md3Music 中。**本期仅聚焦 Android 端**，Windows / Web 端不在范围内。

---

## 二、项目目标

在 md3Music 现有功能基础上，新增一个 **Apple Music 风格逐字歌词模块**，实现以下能力：

| 目标 | 描述 |
|------|------|
| 逐字歌词渲染 | 当歌词数据包含逐字时间戳时，展示 Apple Music 风格的逐字高亮 + 弹性缩放动画 |
| 多格式兼容 | 自动识别并解析 LRC / 增强 LRC（酷狗行内逐字时间戳）/ TTML / 纯文本 |
| 优雅降级 | 无逐字数据时自动降级为整行高亮，不影响正常使用 |
| 原生性能 | 纯 Dart 实现，运行在 Flutter 渲染管线内，零跨进程通信开销 |
| 可扩展 | 新增音源或歌词格式时，只需新增解析器，渲染层和模型层不动 |

---

## 三、参考项目

| 项目 | 地址 | 参考价值 |
|------|------|---------|
| **md3Music** | https://github.com/zzyoxml/md3Music | 主项目，集成目标。基于 Flutter，已有酷狗音源、播放器核心、歌曲搜索、排行榜等功能 |
| **AMLL** | https://github.com/amll-dev/applemusic-like-lyrics | 逐字歌词动画效果参考。TTML/YRC/QRC 解析逻辑、弹性动画曲线、逐字高亮时序设计。其歌词效果已达到甚至超越 Apple Music 原生水平，足以覆盖 UI 参考需求。**注意：仅作设计参考，不能直接用于 Flutter** |

> 已移除：**Cider**（https://github.com/ciderapp/Cider）已于 2024 年 12 月归档；**EchoMusic** 为 md3Music 早期 UI 参考，非必要。

---

## 四、功能需求

### 4.1 歌词格式兼容

模块必须能自动识别并正确解析以下格式：

| 格式 | 来源 | 优先级 | 说明 |
|------|------|--------|------|
| **酷狗增强 LRC** | 酷狗 API 返回 | 最高 | 标准 LRC 行标签 + 行内 `<mm:ss.xx>` 逐字时间戳 |
| **标准 LRC** | 酷狗 API / 本地文件 | 高 | 仅行级时间戳 `[mm:ss.xx]`，无逐字数据 |
| **TTML** | Apple Music 歌词标准 | 中 | XML 格式，内含逐字时间信息 |
| **纯文本** | 本地文件兜底 | 低 | 无任何时间戳，按行展示 |

### 4.2 渲染效果

- **逐字模式**（有逐字时间戳时）：每个字独立计算播放进度，当前字高亮并带弹性缩放动画，已播字变暗，未播字保持原色
- **整行模式**（无逐字时间戳时，降级）：整行按时间渐入渐出，当前行高亮，非当前行降低透明度
- **动画风格**：参照 Apple Music 歌词效果——弹性缩放（类似 `Curves.elasticOut`）、透明度渐变、平滑滚动

### 4.3 播放同步

- 歌词进度与音频播放进度精确同步（毫秒级）
- 支持用户手动拖动歌词定位播放位置
- 支持歌词自动滚动到当前播放行

### 4.4 性能要求

- 渲染帧率稳定在 60fps（Android）/ 120fps（高刷设备）
- 不引入额外进程（不使用 WebView 方案）
- 内存占用增量控制在 5MB 以内

---

## 五、非功能需求

| 维度 | 要求 |
|------|------|
| 技术栈 | 纯 Dart / Flutter，不引入 JS Bridge 或 WebView |
| 代码位置 | 在 md3Music 项目 `lib/widgets/` 下新增 `apple_lyrics/` 模块 |
| 侵入性 | 对 md3Music 现有播放器核心代码的改动最小化 |
| 兼容性 | 仅支持 Android 端（md3Music 的 Windows / Web 端不在本期范围内） |
| 可测试性 | 解析器可独立单元测试，渲染器可脱离播放器单独预览 |
| 协议 | 继承 md3Music 的 MIT 协议 |

---

## 六、架构概要

```
┌──────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  酷狗 API     │────▶│  歌词格式解析器   │────▶│  统一歌词模型     │
│  本地 LRC     │     │  (多格式自动检测)  │     │  (LyricModel)   │
│  TTML 文件    │     └─────────────────┘     └────────┬────────┘
└──────────────┘                                       │
                                                       ▼
┌──────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ just_audio   │────▶│  动画控制器       │────▶│  Apple Music    │
│ (播放进度)    │     │  (AnimationCtrl) │     │  逐字渲染器      │
└──────────────┘     └─────────────────┘     └─────────────────┘
```

### 核心设计原则

1. **统一模型**：所有格式解析为同一个 `LyricLine` 模型，渲染层只认模型，不关心来源
2. **能力标记**：模型自带 `hasWordTiming` 标记，渲染层据此自动切换逐字/整行模式
3. **解析器链**：按优先级依次尝试各解析器，第一个匹配成功的返回结果
4. **优雅降级**：任何格式解析失败都不崩溃，最终兜底到纯文本模式

---

## 七、依赖参考

| 依赖 | 用途 | 说明 |
|------|------|------|
| **Flutter SDK** | 基础框架 | md3Music 已使用 Flutter 3.12+ |
| **just_audio** | 音频播放 | md3Music 已集成，提供播放进度回调 |
| **xml** (pub.dev) | TTML 解析 | 如需支持 TTML 格式，用于解析 XML 结构 |
| **provider** | 状态管理 | md3Music 已使用，歌词状态通过 Provider 传递 |
| **Flutter Animation** | 动画系统 | 内置，`AnimationController` + `Ticker` 驱动逐字动画 |
| **CustomPainter** | 歌词渲染 | 内置，高性能逐字绘制 |

---

## 八、模块划分：沿用现有 vs 二次开发

| 模块 | 分类 | 来源 | 说明 |
|------|------|------|------|
| 音频播放 | ✅ 沿用现有 | md3Music（just_audio） | 已集成，提供播放进度回调，无需改动 |
| 酷狗音源接口 | ✅ 沿用现有 | md3Music（kugou_api_server） | 嵌入式 Node.js 服务器直连酷狗 API，无需改动 |
| 歌曲搜索 / 排行榜 / 推荐 | ✅ 沿用现有 | md3Music | 现有功能完整，无需改动 |
| 歌单管理 / 收藏 / 历史 | ✅ 沿用现有 | md3Music | 现有功能完整，无需改动 |
| 下载管理 | ✅ 沿用现有 | md3Music | 后台下载 + 离线播放，无需改动 |
| 用户登录 / VIP | ✅ 沿用现有 | md3Music（networkapi） | 云端登录 + 自动签到，无需改动 |
| 主题 / 深色模式 | ✅ 沿用现有 | md3Music（MD3 动态配色） | 现有 Material Design 3 主题系统，无需改动 |
| 桌面歌词 | ✅ 沿用现有 | md3Music | 已实现桌面悬浮歌词，无需改动 |
| 播放器 UI 主体 | ✅ 沿用现有 | md3Music | 播放控制栏、进度条、封面等，无需改动 |
| 歌词格式解析器 | 🆕 二次开发 | 参照 AMLL 源码 | LRC / 增强 LRC / TTML / 纯文本多格式解析，Dart 实现 |
| 统一歌词数据模型 | 🆕 二次开发 | 参照 AMLL 源码 | LyricLine / LyricWord 模型，支持能力标记 |
| Apple Music 逐字渲染器 | 🆕 二次开发 | 参照 AMLL 效果 | CustomPainter 实现，逐字高亮 + 弹性缩放动画 |
| 动画控制器 | 🆕 二次开发 | Flutter 内置 | AnimationController + Ticker 驱动，与 just_audio 进度同步 |
| 歌词页 UI 布局 | 🆕 二次开发 | 参照 Apple Music HIG | 替换 md3Music 现有歌词页，改为沉浸式全屏歌词布局 |

### 总结

- **沿用现有**：所有非歌词相关功能，md3Music 已完整实现，零改动
- **二次开发**：仅歌词渲染链路（解析 → 模型 → 渲染 → 同步），全部在 `lib/widgets/apple_lyrics/` 模块内完成
- **对 md3Music 的侵入**：仅需在播放器页面将现有歌词组件替换为 apple_lyrics 组件，其余代码不动

---

## 九、参考资料

- [md3Music GitHub](https://github.com/zzyoxml/md3Music) — 主项目（未归档，活跃维护，v3.2.0 / 2026-07-08）
- [AMLL GitHub](https://github.com/amll-dev/applemusic-like-lyrics) — 逐字歌词动画参考（已从 Steve-xmh 迁移至 amll-dev 组织）
- [AMLL 开发文档](https://applemusic-like-lyrics-docs.vercel.app/) — 歌词组件 API 文档
- [Apple Music 官方设计参考](https://developer.apple.com/design/human-interface-guidelines/music) — 播放界面、歌词布局、交互动效参考
- [Flutter 动画文档](https://docs.flutter.dev/ui/animations) — AnimationController / Tween / CustomPainter
- [just_audio 文档](https://pub.dev/packages/just_audio) — 播放进度回调接口
- [酷狗音乐 API 参考](https://github.com/MakcRe/KuGouMusicApi) — md3Music 使用的 API 代理参考