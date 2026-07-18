# Tasks — add-apple-music-lyrics

> 任务依赖关系见末尾。无依赖的任务可并行。每个任务完成后在 `[ ]` 内打 `x`。

---

## 阶段一：地基（解析器 + 模型 + 弹簧引擎）

这些任务相互独立，可并行开发。是后续所有渲染任务的依赖。

- [x] Task 1: 创建 `lib/widgets/apple_lyrics/` 目录结构并定义统一歌词模型
  - [x] SubTask 1.1: 创建 `lib/widgets/apple_lyrics/models/lyric_line.dart`，定义 `LyricLine` 与 `LyricWord` 类（字段见 spec.md "Requirement: 统一歌词模型"）
  - [x] SubTask 1.2: `LyricWord` 含 `startTime`、`duration`、`text`，`LyricLine` 含 `startTime`、`duration`、`text`、`words`、`translation`，`hasWordTiming` getter
  - [x] SubTask 1.3: 为模型写基础单元测试 `test/widgets/apple_lyrics/models/lyric_line_test.dart`

- [x] Task 2: 实现 KRC 明文解析器
  - [x] SubTask 2.1: 创建 `lib/widgets/apple_lyrics/parsers/krc_parser.dart`
  - [x] SubTask 2.2: 解析 `[start_ms,duration_ms]<offset,duration,0>字...` 行格式，输出 `List<LyricLine>`
  - [x] SubTask 2.3: 过滤 KRC 元数据行（`[id:$...]`、`[ar:...]`、`[ti:...]`、`[total:...]`、`[language:...]`、`[hash:...]`、`[al:...]`、`[sign:...]`、`[qq:...]`、`[offset:...]`），不进入歌词列表
  - [x] SubTask 2.4: 解析失败时返回空列表而非抛异常（优雅降级）
  - [x] SubTask 2.5: 单元测试覆盖：标准行、多字行、元数据过滤、空输入、损坏时间戳、UTF-8 中文（参照 spec.md 附录 B 真实样本「運命の華」）

- [x] Task 3: 实现 LRC 解析器
  - [x] SubTask 3.1: 创建 `lib/widgets/apple_lyrics/parsers/lrc_parser.dart`
  - [x] SubTask 3.2: 解析 `[mm:ss.xx]text` 与 `[mm:ss.xxx]text` 两种时间戳精度，输出 `List<LyricLine>`（`words=[]`，`hasWordTiming=false`）
  - [x] SubTask 3.3: 处理一行多时间戳（如 `[00:01.00][00:30.00]Chorus`）
  - [x] SubTask 3.4: 过滤 LRC 元数据行（`[ar:]`、`[ti:]`、`[al:]`、`[by:]`、`[offset:]`）
  - [x] SubTask 3.5: 单元测试覆盖上述场景

- [x] Task 4: 实现纯文本兜底解析器
  - [x] SubTask 4.1: 创建 `lib/widgets/apple_lyrics/parsers/plaintext_parser.dart`
  - [x] SubTask 4.2: 按行 split，每行生成 `LyricLine(startTime=0, text=line)`，按出现顺序排列
  - [x] SubTask 4.3: 单元测试

- [x] Task 5: 实现解析器链调度器
  - [x] SubTask 5.1: 创建 `lib/widgets/apple_lyrics/parsers/lyric_parser_chain.dart`
  - [x] SubTask 5.2: 按优先级依次尝试 KRC → LRC → 纯文本，第一个解析出非空结果即返回
  - [x] SubTask 5.3: 检测策略：首行匹配 `^\[\d+,\d+\]` 走 KRC；首行匹配 `^\[\d{2}:\d{2}\.\d{2,3}\]` 走 LRC；否则纯文本
  - [x] SubTask 5.4: 单元测试覆盖三种格式自动检测

- [x] Task 6: 实现弹簧物理动画引擎
  - [x] SubTask 6.1: 创建 `lib/widgets/apple_lyrics/animation/spring.dart`
  - [x] SubTask 6.2: 实现临界阻尼弹簧求解器（参照 AMLL `packages/core/src/utils/spring.ts`），公式见 spec.md "Requirement: 弹簧物理动画引擎"
  - [x] SubTask 6.3: 支持欠阻尼与过阻尼两种模式自动切换
  - [x] SubTask 6.4: 到达阈值：位移与一阶/二阶导数均 `< 0.01` 时停止
  - [x] SubTask 6.5: 提供 `setPosition`、`setTarget`、`tick(dt)` 三个核心方法
  - [x] SubTask 6.6: 单元测试：从 0 到 1 的收敛、不同 stiffness/damping 的曲线对比、到达阈值判定

---

## 阶段二：渲染器（依赖阶段一）

- [x] Task 7: 实现逐字 mask alpha 渲染器（核心）
  - [x] SubTask 7.1: 创建 `lib/widgets/apple_lyrics/renderers/word_renderer.dart`
  - [x] SubTask 7.2: 使用 `CustomPainter` 绘制单行歌词，文字颜色固定白色
  - [x] SubTask 7.3: 实现 mask alpha 渐变：已播字 alpha=`dynamicBrightAlpha`，未播字 alpha=`dynamicDarkAlpha`，左亮右暗 `linear-gradient(to right, bright leftPos%, dark ...)`
  - [x] SubTask 7.4: 实现 `factor = clamp01((scale - 0.97) / 0.03)`，`dynamicDarkAlpha = factor*0.2 + 0.2`，`dynamicBrightAlpha = factor*0.8 + 0.2`
  - [x] SubTask 7.5: 实现当前字指数衰减渐变：`ATTACK_SPEED=50.0` 变亮，`RELEASE_SPEED=7.0` 变暗，阈值 0.001
  - [x] SubTask 7.6: 非当前行 SOLID 模式：`bright = dark = dynamicDarkAlpha`（满 scale 时 0.2）
  - [x] SubTask 7.7: 由 `AnimationController` + `Ticker` 驱动每帧重绘

- [x] Task 8: 实现强调辉光（emphasize）效果
  - [x] SubTask 8.1: 创建 `lib/widgets/apple_lyrics/renderers/emphasize_effect.dart`
  - [x] SubTask 8.2: 触发条件：`word.duration >= 1000ms` 且（CJK 任意长度 / 非 CJK 长度 1~7）
  - [x] SubTask 8.3: 实现缩放：`1 + transX * 0.1 * amount`，`amount` 封顶 1.2（最大缩放 1.12）
  - [x] SubTask 8.4: 实现 `textShadow: 0 0 min(0.3, blur*0.3)em rgba(255,255,255, glowLevel)`
  - [x] SubTask 8.5: 末尾字加强：`amount *= 1.6`，`blur *= 1.5`
  - [x] SubTask 8.6: 字符间错位 delay：`wordDe = de + (du / 2.5 / anchorCharCount) * i`
  - [x] SubTask 8.7: bezier 曲线：`bezIn = bezier(0.2, 0.4, 0.58, 1.0)`，`bezOut = bezier(0.3, 0.0, 0.58, 1.0)`（需 Dart 实现 cubic bezier 求值）

- [x] Task 9: 实现间奏点动画
  - [x] SubTask 9.1: 创建 `lib/widgets/apple_lyrics/renderers/interlude_dots.dart`
  - [x] SubTask 9.2: 检测相邻行间隔 `>= 4000ms`，渲染间奏点
  - [x] SubTask 9.3: 提前 250ms 结束间奏动画，准备下一行
  - [x] SubTask 9.4: 参照 AMLL `packages/core/src/lyric-player/dom/interlude-dots.ts` 实现点的呼吸动画

- [x] Task 10: 实现整行降级渲染模式
  - [x] SubTask 10.1: 在 `word_renderer.dart` 中增加 `hasWordTiming=false` 分支
  - [x] SubTask 10.2: 整行按 `startTime` 渐入渐出，当前行高亮，非当前行透明度 0.2
  - [x] SubTask 10.3: 行内无 mask 渐变，整行 SOLID

---

## 阶段三：滚动控制器与布局（依赖阶段二）

- [x] Task 11: 实现歌词滚动控制器
  - [x] SubTask 11.1: 创建 `lib/widgets/apple_lyrics/controllers/lyric_scroll_controller.dart`
  - [x] SubTask 11.2: 用弹簧驱动 `posY`，对齐位置 `alignPosition = 0.35`（不是 0.5）
  - [x] SubTask 11.3: 普通播放：`stiffness = 170 + ratio*50`，`ratio = (1 - (interval-100)/700) ** 0.2`，`damping = sqrt(stiffness)*2.2`
  - [x] SubTask 11.4: seeking / 间奏模式：切换 `stiffness=90, damping=15`
  - [x] SubTask 11.5: overscan = 300px（视口上下额外预渲染）
  - [x] SubTask 11.6: 用户滚动后 5000ms 自动回弹到当前行
  - [x] SubTask 11.7: 点击判定阈值 <10px（小于此视为点击，大于视为滚动）

- [x] Task 12: 实现行缩放动画
  - [x] SubTask 12.1: 当前行 `scale = 1.0`，非当前行 `scale = 0.97`（`enableScale=true`）
  - [x] SubTask 12.2: 背景行：当前 `bgScale = 1.0`，非当前 `bgScale = 0.75`
  - [x] SubTask 12.3: 弹簧参数：主行 `mass=2, damping=25, stiffness=100`，背景行 `mass=1, damping=20, stiffness=50`
  - [x] SubTask 12.4: `transform-origin: left`（对唱行 `right`）

- [x] Task 13: 实现字号与行距布局
  - [x] SubTask 13.1: 字号移动端 `max(8vw, 12px)`，桌面端 `max(max(5vh, 2.5vw), 12px)`（本期 Android，用移动端规则）
  - [x] SubTask 13.2: 行高 `1.2`
  - [x] SubTask 13.3: 行 wrapper padding `0.4em 1em`，内 gap `0.3em`
  - [x] SubTask 13.4: 副行（翻译）：`font-size: max(0.5em, 10px)`，`line-height: 1.5em`，`opacity: 0.3`
  - [x] SubTask 13.5: 背景行（人声）：`opacity: 0.4`，`font-scale: 0.7`

---

## 阶段四：md3Music 集成（依赖阶段三）

- [x] Task 14: 修改 `KugouLyric` 模型支持双请求
  - [x] SubTask 14.1: 在 `lib/services/kugou_api/kugou_models.dart` 的 `KugouLyric` 类新增 `decodedKrcContent` 字段
  - [x] SubTask 14.2: `fromJson` 同时解析 `decodeContent`（LRC）与新字段（KRC）
  - [x] SubTask 14.3: `displayLyric` getter 优先返回 KRC，降级 LRC
  - [x] SubTask 14.4: 单元测试覆盖三种返回场景（KRC+LRC、仅LRC、都空）

- [x] Task 15: 修改 `kugou_api_client.dart` 实现双请求
  - [x] SubTask 15.1: 在 `getLyric` 方法中并发请求 `fmt=lrc` 与 `fmt=krc`（用 `Future.wait`）
  - [x] SubTask 15.2: 任一请求失败不影响另一个（独立 try/catch）
  - [x] SubTask 15.3: 返回 `KugouLyric` 同时携带 `decodedContent` 与 `decodedKrcContent`
  - [x] SubTask 15.4: 兼容现有调用方签名（不破坏 `fmt` 参数，但默认行为变为双请求）

- [x] Task 16: 修改 `kugou_provider.dart` 暴露 KRC
  - [x] SubTask 16.1: `getLyric` 调用新的双请求 `kugou_api_client.getLyric`
  - [x] SubTask 16.2: 暴露 `krcLyric` 与 `lrcLyric` 两个 getter，供 UI 层选择
  - [x] SubTask 16.3: 保留现有 `lyric` getter 兼容旧代码（返回 `krcLyric ?? lrcLyric`）

- [x] Task 17: 创建 `AppleLyricsView` 主组件
  - [x] SubTask 17.1: 创建 `lib/widgets/apple_lyrics/apple_lyrics_view.dart`
  - [x] SubTask 17.2: 接收 `List<LyricLine>` + `currentTime` + `isPlaying` + `onSeek` 回调
  - [x] SubTask 17.3: 集成滚动控制器、行缩放、mask alpha 渲染器、间奏点
  - [x] SubTask 17.4: 整行模式与逐字模式根据 `hasWordTiming` 自动切换
  - [x] SubTask 17.5: 实现点击跳转（点击非当前行调用 `onSeek(line.startTime)`）

- [x] Task 18: 重构 `full_player.dart` 为 Apple Music 风格播放页
  - [x] SubTask 18.1: 替换现有歌词组件为 `AppleLyricsView`
  - [x] SubTask 18.2: 添加模糊封面背景层（`ImageFiltered` + `BackdropFilter`，sigmaX/Y=50）
  - [x] SubTask 18.3: 封面放大填充屏幕居中裁剪，叠加 `rgba(0,0,0,0.35)` 蒙版
  - [x] SubTask 18.4: 封面不可用时降级纯色背景
  - [x] SubTask 18.5: 重做控制栏：上一首/播放暂停/下一首/进度条/时间，全屏页与迷你条两套样式

- [x] Task 19: 实现上滑展开 / 下拉收起手势
  - [x] SubTask 19.1: 在 `full_player.dart` 增加 `GestureDetector` 监听垂直拖动
  - [x] SubTask 19.2: 上滑超过阈值（参照 AMLL：最小触发速度 0.1，点击判定 <10px）展开全屏页
  - [x] SubTask 19.3: 下拉超过阈值或点击下拉按钮收起为迷你播放条
  - [x] SubTask 19.4: 切换动画用弹簧（参数同 Task 6 引擎），duration 由弹簧自然结束决定
  - [x] SubTask 19.5: 迷你条 ↔ 全屏页状态用 `Provider` 或 `ValueNotifier` 管理

- [x] Task 20: 歌词页独立主题应用
  - [x] SubTask 20.1: 歌词文字颜色固定白色 `#FFFFFF`
  - [x] SubTask 20.2: 背景颜色 `rgba(0, 0, 0, 0.35)`
  - [x] SubTask 20.3: mix-blend-mode = `plus-lighter`（Flutter 中用 `BlendMode.plus` 或 `BlendMode.lighten` 模拟）
  - [x] SubTask 20.4: 不读取 md3Music MD3 主题色，确保双主题并存
  - [ ] SubTask 20.5: 可选：从专辑封面提取主色作为模糊背景层（不影响文字颜色）

- [x] Task 21: 处理旧 `lyrics_view.dart` 的替换/移除
  - [x] SubTask 21.1: 评估 `lib/modules/player/lyrics_view.dart` 是否还有其他引用
  - [x] SubTask 21.2: 无引用则删除文件；有引用则保留作为降级兜底（无逐字数据时使用）
  - [x] SubTask 21.3: 若删除，确保 `full_player.dart` 不再导入

---

## 阶段五：测试与预览（依赖阶段四）

- [x] Task 22: 创建渲染预览页
  - [x] SubTask 22.1: 创建 `lib/widgets/apple_lyrics/preview/lyrics_preview_page.dart`
  - [x] SubTask 22.2: 提供文本框输入 KRC/LRC 原文，点击按钮渲染
  - [x] SubTask 22.3: 提供时间滑块模拟播放进度，验证动画时序
  - [x] SubTask 22.4: 不依赖 `just_audio` 与 `KugouProvider`，可独立运行
  - [x] SubTask 22.5: 在 md3Music 路由表中加一个隐藏入口（如设置页长按）打开预览页

- [ ] Task 23: 端到端手动验证清单
  - [ ] SubTask 23.1: 播放有 KRC 的歌曲（如「運命の華」hash=`0DC65949D510244B1ADE85A97602649C`），验证逐字动画
  - [ ] SubTask 23.2: 播放仅有 LRC 的歌曲，验证整行降级
  - [ ] SubTask 23.3: 播放纯音乐（无歌词），验证占位文本
  - [ ] SubTask 23.4: 验证点击跳转、自动滚动、间奏点
  - [ ] SubTask 23.5: 验证上滑展开/下拉收起、模糊封面背景、控制栏样式
  - [ ] SubTask 23.6: 验证性能：60fps 稳定（用 Flutter DevTools Performance 面板）
  - [ ] SubTask 23.7: 验证内存占用增量 < 5MB（用 DevTools Memory 面板）

---

# Task Dependencies

- **Task 1（模型）** → 无依赖，最先开始
- **Task 2/3/4（解析器）** → 依赖 Task 1，三者互相独立可并行
- **Task 5（解析器链）** → 依赖 Task 2/3/4
- **Task 6（弹簧引擎）** → 无依赖，可与 Task 1~5 并行
- **Task 7（mask alpha 渲染）** → 依赖 Task 1（模型）+ Task 6（弹簧）
- **Task 8（强调辉光）** → 依赖 Task 7
- **Task 9（间奏点）** → 依赖 Task 6
- **Task 10（整行降级）** → 依赖 Task 7
- **Task 11（滚动控制器）** → 依赖 Task 6
- **Task 12（行缩放）** → 依赖 Task 6 + Task 7
- **Task 13（字号布局）** → 依赖 Task 1
- **Task 14（KugouLyric 模型改）** → 无依赖，可与阶段一/二并行
- **Task 15（api_client 双请求）** → 依赖 Task 14
- **Task 16（provider 暴露）** → 依赖 Task 15
- **Task 17（AppleLyricsView）** → 依赖 Task 5/7/8/9/10/11/12/13 全部
- **Task 18（full_player 重构）** → 依赖 Task 16 + Task 17
- **Task 19（手势）** → 依赖 Task 18
- **Task 20（独立主题）** → 依赖 Task 18
- **Task 21（旧 lyrics_view 处理）** → 依赖 Task 18
- **Task 22（预览页）** → 依赖 Task 17
- **Task 23（端到端验证）** → 依赖所有任务

## 可并行批次建议

- **批次 A**（最先）：Task 1、Task 6、Task 14（三者完全独立）
- **批次 B**：Task 2、Task 3、Task 4、Task 13（依赖批次 A 的 Task 1）
- **批次 C**：Task 5（依赖批次 B）、Task 7、Task 9、Task 11、Task 15（依赖 Task 14）
- **批次 D**：Task 8、Task 10、Task 12、Task 16（依赖批次 C）
- **批次 E**：Task 17（依赖所有渲染器+控制器）
- **批次 F**：Task 18、Task 21、Task 22（依赖 Task 17）
- **批次 G**：Task 19、Task 20（依赖 Task 18）
- **批次 H**：Task 23（最终验证）
