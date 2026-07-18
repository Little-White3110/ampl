# Apple Music 风格歌词与播放页模块 Spec

> change-id: `add-apple-music-lyrics`
> 来源：基于 `md3Music-AppleLyrics-PRD.md` v1.3，经 `/grilling` 会话质询后落地
> 日期：2026-07-18

---

## Why

md3Music 当前歌词页只有整行高亮（`lib/modules/player/lyrics_view.dart`），且默认请求酷狗 `fmt=lrc`，**根本不获取逐字时间戳**——`kugou_api_server/util/util.js` 里的 KRC 解码（XOR+zlib）是死代码。要实现 Apple Music 风格逐字动画，必须同时改请求参数、解析器、渲染器、播放页布局。PRD v1.3 低估了三件事：(1) 酷狗逐字格式是 KRC（base64+XOR+zlib），不是"增强 LRC 行内 `<mm:ss.xx>` 时间戳"；(2) 用户要求"1:1 复刻 Apple Music 播放页"，远超 PRD 4.2 节的"歌词渲染"范围；(3) md3Music 默认走 LRC 路径，逐字能力完全闲置。

## What Changes

### 模块新增（`lib/widgets/apple_lyrics/`）
- **KRC 明文解析器**：解析 `[start_ms,duration_ms]<offset,duration,0>字...` 格式，输出统一 `LyricLine` 模型
- **LRC 解析器**：解析 `[mm:ss.xx]text`，输出无 `wordTiming` 的 `LyricLine`
- **纯文本兜底解析器**：无时间戳按行输出
- **统一歌词模型**：`LyricLine` / `LyricWord`，带 `hasWordTiming` 能力标记
- **弹簧物理动画引擎**：自实现临界阻尼弹簧求解器（参照 AMLL `packages/core/src/utils/spring.ts`）
- **逐字渲染器**：`CustomPainter` + mask alpha 渐变，实现"已播字亮 / 未播字暗"效果
- **滚动控制器**：弹簧驱动 posY，对齐位置 0.35，overscan 300px，间奏阈值 4000ms
- **歌词页 UI**：模糊封面背景 + 歌词主体 + 自动滚动 + 点击跳转

### md3Music 代码改动（侵入点）
- **`lib/services/kugou_api/kugou_api_client.dart`**：`getLyric` 方法**双请求** lrc + krc，返回 `KugouLyric` 同时携带两种明文
- **`lib/services/kugou_api/kugou_models.dart`**：`KugouLyric` 新增 `decodedKrcContent` 字段
- **`lib/providers/kugou_provider.dart`**：`getLyric` 同时拉取 krc，暴露 `krcLyric` 与 `lrcLyric`
- **`lib/modules/player/full_player.dart`**：将现有歌词组件替换为 `AppleLyricsView`，整体播放页改造为 Apple Music 风格
- **`lib/modules/player/lyrics_view.dart`**：保留作为降级兜底，或整体移除（决策点见下）

### 范围扩张（用户在 grilling 中明确要求，超出 PRD 4.2）
- **模糊封面背景**：全屏 `ImageFiltered` + `BackdropFilter` 模糊放大专辑封面
- **上滑展开 / 下拉收起**：手势驱动播放页在"迷你播放条 ↔ 全屏播放页"之间切换
- **控制栏重做**：播放/暂停/上一首/下一首/进度条按 Apple Music HIG 重做样式
- **页面切换动画**：展开/收起的弹簧过渡动画
- **歌词页独立主题**：歌词页用 Apple Music 风格（高对比黑白 + 封面取色），**不受 md3Music MD3 动态主题影响**——双主题并存

### **BREAKING**
- md3Music 现有 `lyrics_view.dart` 将被 `AppleLyricsView` 替换，原整行高亮逻辑废弃
- 现有 `full_player.dart` 整页布局重构，原 MD3 风格播放页布局不再使用
- 用户已装的 md3Music 升级后，播放页外观会显著变化（从 MD3 变为 Apple Music 风格）

### 本期不做
- **TTML 解析**：酷狗 API 不返回 TTML，无数据源，砍掉（PRD 4.1 表中 TTML 行移除）
- **拖动歌词跳转**：用户只要"自动滚动 + 点击跳转"，不做拖动跳转
- **长按菜单**：不做长按复制/收藏等额外操作
- **Windows / Web 端**：仅 Android
- **桌面歌词改动**：md3Music 现有桌面歌词不动
- **测试**：不写 golden test，不做集成测试（仅单元测试 + 渲染预览页）

## Impact

- **Affected specs**: 无（这是首个 spec）
- **Affected code**:
  - 新增：`lib/widgets/apple_lyrics/` 整个目录（解析器、模型、渲染器、动画引擎、UI）
  - 修改：`lib/services/kugou_api/kugou_api_client.dart`、`kugou_models.dart`、`lib/providers/kugou_provider.dart`、`lib/modules/player/full_player.dart`
  - 废弃/替换：`lib/modules/player/lyrics_view.dart`
  - Node 侧不动：`kugou_api_server/util/util.js` 的 `decodeLyrics` 已存在，只需 Dart 端传 `fmt=krc` 即可激活
- **Affected deps**:
  - 不引入新依赖（不引 `xml` 包，因为砍了 TTML）
  - 不引 WebView / JS Bridge
  - 复用 md3Music 现有：`just_audio`、`provider`、Flutter 内置 `AnimationController` / `CustomPainter`

---

## ADDED Requirements

### Requirement: KRC 双请求与降级

系统 SHALL 在获取歌词时同时请求 `fmt=lrc` 与 `fmt=krc` 两种格式，Dart 端优先使用 KRC 明文（含逐字时间戳），KRC 不可用时降级到 LRC（仅行级时间戳），两者都不可用时降级到纯文本。

#### Scenario: KRC 可用
- **WHEN** 酷狗 API 对某歌曲同时返回有效的 KRC 和 LRC
- **THEN** `KugouLyric.decodedKrcContent` 与 `decodedContent` 均有值
- **AND** 渲染器优先使用 `decodedKrcContent`，进入逐字模式

#### Scenario: KRC 不可用但 LRC 可用
- **WHEN** 酷狗 API 仅返回 LRC（KRC 解码失败或为空）
- **THEN** `decodedKrcContent` 为 null，`decodedContent` 有值
- **AND** 渲染器降级为整行模式，`hasWordTiming = false`

#### Scenario: 两者都不可用
- **WHEN** KRC 与 LRC 均为空（如纯音乐）
- **THEN** 显示"无歌词"占位或纯文本兜底

### Requirement: KRC 明文解析

系统 SHALL 解析 KRC 明文格式（`[start_ms,duration_ms]<offset,duration,0>字...`）为 `List<LyricLine>`，每个 `LyricLine` 包含 `List<LyricWord>`，每个 `LyricWord` 携带 `startTime`、`duration`、`text`。

#### Scenario: 标准 KRC 行
- **GIVEN** KRC 行 `[12500,4200]<0,300,0>运<300,400,0>命<700,500,0>的<1200,600,0>华`
- **THEN** 解析出 `LyricLine(startTime=12500, duration=4200)`，含 4 个 `LyricWord`
- **AND** 第一个 `LyricWord(startTime=12500, duration=300, text="运")`

#### Scenario: KRC 元数据行过滤
- **GIVEN** KRC 文件头的 `[id:$00000000]`、`[ar:...]`、`[ti:...]`、`[total:195735]`、`[language:...]` 等元数据
- **THEN** 这些行不进入 `List<LyricLine>`，但 `[language:...]` 中的翻译/音译 SHALL 被提取为 `LyricLine.translation`（可选，本期可先不实现）

### Requirement: 统一歌词模型

系统 SHALL 提供统一 `LyricLine` 模型，渲染层只认模型不关心来源。

```dart
class LyricWord {
  final int startTime;  // 毫秒，绝对时间
  final int duration;   // 毫秒
  final String text;
}

class LyricLine {
  final int startTime;       // 毫秒
  final int duration;        // 毫秒
  final String text;         // 整行纯文本
  final List<LyricWord> words; // 可能为空（LRC/纯文本）
  final String? translation; // 翻译，可空
  bool get hasWordTiming => words.isNotEmpty;
}
```

#### Scenario: LRC 解析结果
- **GIVEN** LRC 行 `[01:23.45]Hello World`
- **THEN** `LyricLine(startTime=83450, text="Hello World", words=[])`
- **AND** `hasWordTiming = false`，渲染器降级为整行模式

### Requirement: 弹簧物理动画引擎

系统 SHALL 自实现临界阻尼弹簧求解器（不依赖第三方库），参照 AMLL `packages/core/src/utils/spring.ts`。

#### Scenario: 行缩放弹簧
- **WHEN** 行从非当前（scale=0.97）过渡到当前（scale=1.0）
- **THEN** 使用 `mass=2, damping=25, stiffness=100` 弹簧参数
- **AND** 每帧推进，直到位移与一阶/二阶导数均 `< 0.01` 时停止

#### Scenario: posY 滚动弹簧（普通播放）
- **WHEN** 自动滚动到当前行
- **THEN** `stiffness = 170 + ratio*50`（ratio 由相邻行间隔 100~800ms 映射），`damping = sqrt(stiffness)*2.2`
- **AND** `alignPosition = 0.35`（行中心位于视口高度 35% 处，不是 50%）

#### Scenario: posY 滚动弹簧（seeking/间奏）
- **WHEN** 用户拖动进度条或处于间奏
- **THEN** 切换到 `stiffness=90, damping=15`（更稳定，避免抖动）

### Requirement: 逐字 mask alpha 渲染

系统 SHALL 使用 mask alpha 渐变（非颜色切换）区分已播/未播字。文字本身只有一种颜色（默认白色），通过 mask alpha 实现"已播亮、未播暗"。

#### Scenario: 当前行逐字渲染
- **GIVEN** 当前行 `hasWordTiming = true` 且处于播放中
- **THEN** 已播字 alpha = `dynamicBrightAlpha`（满 scale 时 **1.0**）
- **AND** 未播字 alpha = `dynamicDarkAlpha`（满 scale 时 **0.4**）
- **AND** 当前字按 `ATTACK_SPEED=50.0` 指数渐变变亮，按 `RELEASE_SPEED=7.0` 指数渐变变暗
- **AND** mask 渐变方向：左亮右暗 `linear-gradient(to right, bright leftPos%, dark ...)`

#### Scenario: 非当前行渲染
- **THEN** 整行 SOLID 模式，`bright = dark = dynamicDarkAlpha`（满 scale 时 **0.2**），全行均匀变暗

#### Scenario: scale 与 alpha 联动
- **WHEN** 行 scale 从 0.97 → 1.0 过渡
- **THEN** `factor = clamp01((scale - 0.97) / 0.03)`
- **AND** `dynamicDarkAlpha = factor * 0.2 + 0.2`（0.2~0.4）
- **AND** `dynamicBrightAlpha = factor * 0.8 + 0.2`（0.2~1.0）

### Requirement: 强调辉光（emphasize）效果

系统 SHALL 对时长 `>= 1000ms` 的字（CJK 任意长度 / 非 CJK 长度 1~7）触发强调辉光动画。

#### Scenario: 触发辉光
- **GIVEN** 某 `LyricWord.duration >= 1000` 且为 CJK 字符
- **THEN** 缩放最大约 **1.12**（`1 + transX * 0.1 * amount`，`amount` 封顶 1.2）
- **AND** 辉光 `textShadow: 0 0 min(0.3, blur*0.3)em rgba(255,255,255, glowLevel)`
- **AND** 末尾字加强：`amount *= 1.6`，`blur *= 1.5`
- **AND** 字符间错位 delay：`wordDe = de + (du / 2.5 / anchorCharCount) * i`

### Requirement: 间奏点动画

系统 SHALL 在相邻行间隔 `>= 4000ms` 时显示间奏点动画。

#### Scenario: 进入间奏
- **WHEN** 检测到下一行 startTime - 当前行 endTime >= 4000ms
- **THEN** 显示间奏点（参照 AMLL `interlude-dots.ts`）
- **AND** 提前 250ms 结束间奏动画，准备下一行

### Requirement: 歌词页独立主题

歌词页 SHALL 使用独立主题，不受 md3Music MD3 动态主题影响。

#### Scenario: 默认颜色
- **THEN** 歌词文字颜色 = 白色（`#FFFFFF`）
- **AND** 背景颜色 = `rgba(0, 0, 0, 0.35)` 半透明黑
- **AND** mix-blend-mode = `plus-lighter`（加色混合）

#### Scenario: 封面取色（可选）
- **WHEN** 专辑封面可用
- **THEN** 从封面提取主色作为背景模糊层（不影响文字颜色，文字始终白色）

### Requirement: 字号与行距

系统 SHALL 按以下参数设置字号与行距：

| 参数 | 值 |
|------|----|
| 字号（移动端） | `max(8vw, 12px)` |
| 行高 | `1.2` |
| 行 wrapper padding | `0.4em 1em` |
| 行 wrapper 内 gap | `0.3em` |
| 副行（翻译）font-size | `max(0.5em, 10px)` |
| 副行 line-height | `1.5em` |
| 副行 opacity | `0.3` |
| 背景行（人声）opacity | `0.4` |
| 背景行 font-scale | `0.7` |

### Requirement: 模糊封面背景

系统 SHALL 在播放页背景层渲染模糊放大的专辑封面。

#### Scenario: 封面可用
- **THEN** `ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50))` + `BackdropFilter`
- **AND** 封面放大至填充屏幕，居中裁剪
- **AND** 叠加半透明黑色蒙版（`rgba(0,0,0,0.35)`）保证歌词可读性

#### Scenario: 封面不可用
- **THEN** 降级为纯色背景（默认 md3Music MD3 主色或纯黑）

### Requirement: 上滑展开 / 下拉收起

系统 SHALL 支持手势在"迷你播放条 ↔ 全屏播放页"之间切换。

#### Scenario: 上滑展开
- **WHEN** 用户在迷你播放条上向上滑动超过阈值（参照 AMLL `scroll.ts`：最小触发速度 0.1，点击判定 <10px）
- **THEN** 全屏播放页弹簧展开，迷你条淡出
- **AND** 切换动画用弹簧曲线，duration 由弹簧自然结束决定

#### Scenario: 下拉收起
- **WHEN** 用户在全屏播放页顶部向下拉超过阈值或点击下拉按钮
- **THEN** 全屏页弹簧收起为迷你条

### Requirement: 控制栏重做

系统 SHALL 按 Apple Music HIG 重做播放控制栏。

#### Scenario: 控制栏元素
- **THEN** 包含：上一首、播放/暂停、下一首、进度条、当前时间/总时长、封面缩略图、歌曲标题/艺术家
- **AND** 全屏页控制栏样式与迷你条样式分别设计（全屏页大按钮居中，迷你条紧凑横排）

### Requirement: 点击跳转

系统 SHALL 支持点击歌词行跳转播放位置。

#### Scenario: 点击非当前行
- **WHEN** 用户点击某行歌词
- **AND** 该行 `startTime` 有效
- **THEN** 调用 `just_audio.seek(line.startTime)`
- **AND** 滚动弹簧立即对齐到该行

### Requirement: 单元测试与渲染预览页

系统 SHALL 提供解析器单元测试与渲染器预览页。

#### Scenario: 解析器单元测试
- **THEN** KRC 解析器、LRC 解析器、纯文本解析器各有独立单元测试
- **AND** 测试覆盖正常格式、边界情况（空行、元数据行、损坏时间戳）、降级路径

#### Scenario: 渲染预览页
- **THEN** 提供独立预览页（无需连接播放器），可手动输入 KRC/LRC 文本预览渲染效果
- **AND** 预览页可拖动模拟时间进度，验证动画时序

---

## MODIFIED Requirements

### Requirement: md3Music 歌词获取链路（修改自 PRD 4.1）

[原 PRD 4.1 描述错误：将酷狗格式描述为"标准 LRC 行标签 + 行内 `<mm:ss.xx>` 逐字时间戳"。实际酷狗逐字格式是 KRC，需要 base64 + XOR + zlib 解码，明文格式为 `[start_ms,duration_ms]<offset,duration,0>字`。]

修改后的歌词格式优先级：

| 格式 | 来源 | 优先级 | 说明 |
|------|------|--------|------|
| **KRC 明文** | 酷狗 API `fmt=krc`，经 Node 侧 `decodeLyrics`（base64+XOR+zlib）解码 | 最高 | 行级 `[ms,ms]` + 字级 `<ms,ms,0>`，毫秒精度 |
| **标准 LRC** | 酷狗 API `fmt=lrc`，Node 侧仅 base64 解码 | 高 | 行级 `[mm:ss.xx]`，无逐字 |
| **纯文本** | 兜底 | 低 | 无时间戳 |

**双请求策略**：Dart 端同时发起 lrc + krc 请求，krc 优先，失败降级 lrc。

### Requirement: md3Music 播放页布局（修改自 PRD 6 节架构图）

[原 PRD 6 节只描述歌词渲染链路，未涉及播放页整体布局。用户在 grilling 中明确要求"1:1 复刻 Apple Music 播放页 + 含手势交互"，本节扩展架构。]

修改后架构：

```
┌─────────────────────────────────────────────────────────┐
│  模糊封面背景层（ImageFiltered + BackdropFilter）        │
├─────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────┐  │
│  │  顶部下拉手柄 + 歌曲标题/艺术家                     │  │
│  ├───────────────────────────────────────────────────┤  │
│  │                                                   │  │
│  │            AppleLyricsView（逐字渲染）             │  │
│  │            - 滚动控制器（弹簧 posY）               │  │
│  │            - 间奏点动画                            │  │
│  │                                                   │  │
│  ├───────────────────────────────────────────────────┤  │
│  │  控制栏（上一首/播放/下一首/进度条/时间）          │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
        ↑ 下拉收起为迷你播放条
        ↓ 上滑展开为全屏播放页
```

---

## REMOVED Requirements

### Requirement: TTML 格式支持

**Reason**: 酷狗 API 不返回 TTML 格式，无数据源。PRD 4.1 表中的 TTML 行在本期移除。
**Migration**: 如未来需要 TTML 支持（如本地 .ttml 文件解析），按"解析器链"架构新增 `TtmlParser` 即可，渲染层和模型层无需改动。

### Requirement: 拖动歌词跳转 / 长按菜单

**Reason**: 用户在 grilling 中明确不需要，只要"自动滚动 + 点击跳转"。
**Migration**: 无。

### Requirement: 酷狗增强 LRC 格式（行内 `<mm:ss.xx>` 逐字时间戳）

**Reason**: PRD 4.1 表对酷狗格式的描述是错误的。酷狗的逐字格式是 KRC（base64+XOR+zlib 编码，明文为 `[ms,ms]`+`<ms,ms,0>`），不是"标准 LRC + 行内 `<mm:ss.xx>`"。原描述的格式不存在。
**Migration**: 用 KRC 明文解析器替代。

---

## 附录 A：md3Music 现有调用链（来自 grilling 调研）

```
[full_player.dart]  getLyric(songId, songName)          ← 不传 fmt
        ↓
[kugou_provider]    getLyric(hash, fmt='lrc')            ← 默认 lrc
        ↓
[kugou_api_client]  getLyric(hash, fmt='lrc', decode=true)
        ↓  HTTP GET http://127.0.0.1:8080/lyric?id=xxx&fmt=lrc&decode=true&accesskey=xxx
        ↓
[node lyric.js]     请求 https://lyrics.kugou.com/download?fmt=lrc
        ↓  收到 base64 content
        ↓  因 fmt=='lrc' → Buffer.from(content,'base64').toString()  ← 仅 base64 解码
        ↓  挂上 body.decodeContent = 明文LRC
        ↓
[kugou_models]      KugouLyric.fromJson → decodedContent = 明文LRC
        ↓  displayLyric => decodedContent ?? content  = 明文LRC
        ↓
[lyrics_view]       _parseLyrics() 用 LRC 正则 \[(\d{2}):(\d{2})\.(\d{2,3})\] 解析
```

**关键文件**：
- `kugou_api_server/module/lyric.js`（Node 侧歌词接口）
- `kugou_api_server/util/util.js`（`decodeLyrics` 函数，KRC 解码已实现但是死代码）
- `lib/services/kugou_api/kugou_endpoints.dart`（接口名常量）
- `lib/services/kugou_api/kugou_api_client.dart:758-816`（`getLyric` 方法）
- `lib/services/kugou_api/kugou_models.dart:670-696`（`KugouLyric` 模型）
- `lib/providers/kugou_provider.dart:413-445`（Provider 包装层）
- `lib/modules/player/full_player.dart:90-98`（UI 调用方）
- `lib/modules/player/lyrics_view.dart:121-173`（现有 LRC 解析，将被替换）
- `lib/services/nodejs_server.dart`（Node 服务器内嵌启动逻辑）

## 附录 B：AMLL 关键参数速查（来自 grilling 调研）

### 弹簧参数（`packages/core/src/lyric-player/base/index.ts:103-122`）
| 用途 | mass | damping | stiffness |
|------|------|---------|-----------|
| 行缩放（主行） | 2 | 25 | 100 |
| 行缩放（背景行） | 1 | 20 | 50 |
| posY（seeking/间奏） | — | 15 | 90 |
| posY（普通播放） | — | `sqrt(stiffness)*2.2` | 170~220（动态） |

### 行为参数
- 当前行 scale = 1.0，非当前行 scale = 0.97（`enableScale=true` 时）
- 背景行：非当前 0.75，当前 1.0
- 对齐位置 `alignPosition = 0.35`
- overscan = 300px
- 间奏阈值 = 4000ms，间奏提前结束 = 250ms
- 点击判定阈值 = 10px
- 用户滚动后自动回弹超时 = 5000ms
- 惯性摩擦 = `0.95 ** (dt/16)`，最小惯性速度 = 0.05

### alpha 参数（`lyric-line.ts:921-973`）
- `currentBrightAlpha = 1.0`，`currentDarkAlpha = 0.2`
- `dynamicDarkAlpha = factor*0.2 + 0.2`（0.2~0.4）
- `dynamicBrightAlpha = factor*0.8 + 0.2`（0.2~1.0）
- `factor = clamp01((scale - 0.97) / 0.03)`
- `ATTACK_SPEED = 50.0`，`RELEASE_SPEED = 7.0`
- alpha 渐变阈值 = 0.001

### 强调辉光参数（`lyric-line.ts:510-651`）
- 触发条件：`duration >= 1000ms` 且（CJK 任意长度 / 非 CJK 长度 1~7）
- 最大缩放 ≈ 1.12
- bezier 曲线：`bezIn = bezier(0.2, 0.4, 0.58, 1.0)`，`bezOut = bezier(0.3, 0.0, 0.58, 1.0)`
- 末尾字加强：`amount *= 1.6`，`blur *= 1.5`

### CSS / 字号参数（`lyric-player.module.css` / `index.css`）
- 字号移动端：`max(8vw, 12px)`
- 行高：`1.2`
- 行 wrapper padding：`0.4em 1em`
- 行 wrapper gap：`0.3em`
- 副行：`font-size: max(0.5em, 10px)`，`line-height: 1.5em`，`opacity: 0.3`
- 背景行：`opacity: 0.4`，`font-scale: 0.7`
- 缩放基准点：`transform-origin: left`（对唱行 `right`）
- 文字颜色：`white`，mix-blend-mode：`plus-lighter`
- 背景：`rgba(0, 0, 0, 0.35)`
