# Checklist — add-apple-music-lyrics

> 实现完成后逐项验证。每项需在代码中找到证据，不能仅凭"看起来对"打勾。
>
> 本轮静态验证：环境未安装 Flutter SDK，无法运行 `flutter test` / `flutter analyze`。
> 所有勾选项均通过 Read/Grep 在代码中找到直接证据；保持 `[ ]` 的项为需要运行动态验证或代码中确未实现。

---

## 阶段一：地基（解析器 + 模型 + 弹簧引擎）

- [x] `lib/widgets/apple_lyrics/models/lyric_line.dart` 存在且定义了 `LyricLine` 与 `LyricWord` 类
- [x] `LyricLine` 字段完整：`startTime`、`duration`、`text`、`words`、`translation`、`hasWordTiming` getter
- [x] `LyricWord` 字段完整：`startTime`、`duration`、`text`
- [x] KRC 解析器 `krc_parser.dart` 能正确解析 `[start_ms,duration_ms]<offset,duration,0>字` 格式
- [x] KRC 解析器能过滤元数据行（`[id:$...]`、`[ar:...]`、`[ti:...]`、`[total:...]` 等）
- [x] KRC 解析器解析失败时返回空列表，不抛异常
- [x] LRC 解析器 `lrc_parser.dart` 能解析 `[mm:ss.xx]` 与 `[mm:ss.xxx]` 两种精度
- [x] LRC 解析器能处理一行多时间戳（`[00:01.00][00:30.00]Chorus`）
- [x] 纯文本解析器 `plaintext_parser.dart` 按行输出 `LyricLine`
- [x] 解析器链 `lyric_parser_chain.dart` 按优先级 KRC → LRC → 纯文本自动检测
- [x] 自动检测策略：首行 `^\[\d+,\d+\]` 走 KRC，`^\[\d{2}:\d{2}\.\d{2,3}\]` 走 LRC
- [x] 弹簧引擎 `spring.dart` 实现临界阻尼求解器，公式与 AMLL `spring.ts` 一致
- [x] 弹簧到达阈值：位移与一阶/二阶导数均 `< 0.01` 时停止
- [x] 弹簧支持 `setPosition`、`setTarget`、`tick(dt)` 三个核心方法
- [ ] 阶段一所有单元测试通过（`flutter test test/widgets/apple_lyrics/`） — 需 Flutter SDK 动态运行，环境未安装

## 阶段二：渲染器

- [x] `word_renderer.dart` 使用 `CustomPainter` 绘制单行歌词（由外部 CustomPainter 调用 `paintLine`）
- [x] 文字颜色固定白色，靠 mask alpha 区分已播/未播
- [x] 已播字 alpha=`dynamicBrightAlpha`（满 scale 时 1.0），未播字 alpha=`dynamicDarkAlpha`（满 scale 时 0.4）
- [x] mask 渐变方向：左亮右暗（按 word 索引计算 alpha，已播字在左亮，未播字在右暗）
- [x] `factor = clamp01((scale - 0.97) / 0.03)` 计算正确
- [x] `dynamicDarkAlpha = factor*0.2 + 0.2`，`dynamicBrightAlpha = factor*0.8 + 0.2` 计算正确
- [x] 当前字指数衰减：`ATTACK_SPEED=50.0` 变亮，`RELEASE_SPEED=7.0` 变暗，阈值 0.001
- [x] 非当前行 SOLID 模式：`bright = dark = dynamicDarkAlpha`（scale=0.97 时 0.2）
- [x] 渲染由 `Ticker`（`createTicker`）驱动每帧重绘，等价于 `AnimationController + Ticker`
- [x] 强调辉光触发条件：`word.duration >= 1000ms` 且（CJK 任意长度 / 非 CJK 长度 1~7）
- [x] 强调辉光最大缩放约 1.12（`1 + transX * 0.1 * amount`，amount 封顶 1.2）
- [x] 强调辉光末尾字加强：`amount *= 1.6`，`blur *= 1.5`
- [x] 强调辉光字符间错位 delay 公式实现（`wordDe = de + (du / 2.5 / anchorCharCount) * i`）
- [x] bezier 曲线 `bezIn = bezier(0.2, 0.4, 0.58, 1.0)`，`bezOut = bezier(0.3, 0.0, 0.58, 1.0)` 在 Dart 中正确求值
- [x] 间奏点动画在相邻行间隔 `>= 4000ms` 时显示
- [x] 间奏点提前 250ms 结束，准备下一行
- [x] 整行降级模式：`hasWordTiming=false` 时整行渐入渐出，非当前行透明度 0.2

## 阶段三：滚动控制器与布局

- [x] 滚动控制器用弹簧驱动 `posY`
- [x] 对齐位置 `alignPosition = 0.35`（不是 0.5）
- [x] 普通播放 `stiffness = 170 + ratio*50`，`ratio = (1 - (interval-100)/700) ** 0.2`，`damping = sqrt(stiffness)*2.2`
- [x] seeking/间奏模式 `stiffness=90, damping=15`
- [x] overscan = 300px
- [x] 用户滚动后 5000ms 自动回弹到当前行
- [x] 点击判定阈值 <10px
- [x] 当前行 `scale = 1.0`，非当前行 `scale = 0.97`
- [x] 背景行：当前 `bgScale = 1.0`，非当前 `bgScale = 0.75`
- [x] 主行弹簧参数 `mass=2, damping=25, stiffness=100`
- [x] 背景行弹簧参数 `mass=1, damping=20, stiffness=50`
- [x] 缩放基准点 `transform-origin: left`（对唱行 `right`）
- [x] 字号移动端 `max(8vw, 12px)`
- [x] 行高 `1.2`
- [x] 行 wrapper padding `0.4em 1em`，内 gap `0.3em`
- [x] 副行 `font-size: max(0.5em, 10px)`，`line-height: 1.5em`，`opacity: 0.3`
- [x] 背景行 `opacity: 0.4`，`font-scale: 0.7`

## 阶段四：md3Music 集成

- [x] `KugouLyric` 类新增 `decodedKrcContent` 字段
- [x] `KugouLyric.fromJson` 同时解析 `decodeContent`（LRC）与 `decodedKrcContent`（KRC）
- [x] `displayLyric` getter 优先返回 KRC，降级 LRC
- [x] `kugou_api_client.getLyric` 并发请求 `fmt=lrc` 与 `fmt=krc`（`Future.wait`）
- [x] 双请求中任一失败不影响另一个（独立 try/catch）
- [x] 兼容现有调用方签名（不破坏 `fmt` 参数）
- [x] `kugou_provider.getLyric` 调用新的双请求方法
- [x] Provider 暴露 `krcLyric` 与 `lrcLyric` 两个 getter
- [x] 保留 `lyric` getter 兼容旧代码（返回 `krcLyric ?? lrcLyric`）
- [x] `AppleLyricsView` 接收 `List<LyricLine>` + `currentTime` + `isPlaying` + `onSeek` 回调
- [x] `AppleLyricsView` 集成滚动控制器、行缩放、mask alpha 渲染器、间奏点
- [x] 整行模式与逐字模式根据 `hasWordTiming` 自动切换
- [x] 点击非当前行调用 `onSeek(line.startTime)`
- [x] `full_player.dart` 中现有歌词组件已替换为 `AppleLyricsView`
- [x] 模糊封面背景层：`ImageFiltered` + `ImageFilter.blur`，sigmaX/Y=50（实现等价于 spec 描述的 `ImageFiltered + BackdropFilter`）
- [x] 封面放大填充屏幕居中裁剪，叠加 `rgba(0,0,0,0.35)` 蒙版（`Color(0x59000000)`）
- [x] 封面不可用时降级纯色背景（`ColoredBox(color: Colors.black)`）
- [x] 控制栏重做：上一首/播放暂停/下一首/进度条/时间齐全
- [x] 全屏页控制栏与迷你条控制栏两套样式分别实现
- [x] 上滑超过阈值展开全屏页（速度 < -100 px/s 或距离 < -100 px）
- [x] 下拉超过阈值或点击下拉按钮收起为迷你播放条
- [x] 切换动画用弹簧曲线（`_expansionSpring`，mass=1, damping=20, stiffness=100）
- [x] 迷你条 ↔ 全屏页状态用 `StatefulWidget` 内部 `_isExpanded` 字段 + `Spring` 驱动进度（等价于 `Provider`/`ValueNotifier` 状态管理）
- [x] 歌词文字颜色固定白色 `#FFFFFF`
- [x] 背景颜色 `rgba(0, 0, 0, 0.35)`
- [ ] `mix-blend-mode: plus-lighter` 在 Flutter 中用 `BlendMode.plus` 或 `BlendMode.lighten` 模拟 — 代码中未找到 `BlendMode.plus` / `BlendMode.lighten` 使用，未实现
- [x] 不读取 md3Music MD3 主题色，确保双主题并存（歌词文字直接用 `Colors.white` / `Color.fromRGBO`）
- [x] 旧 `lyrics_view.dart` 已删除（Glob 确认不存在）

## 阶段五：测试与预览

- [x] 预览页 `lyrics_preview_page.dart` 提供文本框输入 KRC/LRC 原文
- [x] 预览页提供时间滑块模拟播放进度
- [x] 预览页不依赖 `just_audio` 与 `KugouProvider`，可独立运行
- [x] 预览页在 md3Music 路由表中有隐藏入口（`settings_page.dart` L416-427 跳转 `LyricsPreviewPage`）

## 端到端手动验证（Task 23）

> 以下 7 项需用户在 Flutter 环境中实际运行 app 验证，静态检查无法覆盖，保持 `[ ]`。

- [ ] 播放有 KRC 的歌曲（如「運命の華」hash=`0DC65949D510244B1ADE85A97602649C`），逐字动画正常
- [ ] 播放仅有 LRC 的歌曲，整行降级模式正常
- [ ] 播放纯音乐（无歌词），占位文本显示
- [ ] 点击跳转、自动滚动、间奏点均正常
- [ ] 上滑展开/下拉收起、模糊封面背景、控制栏样式正常
- [ ] Flutter DevTools Performance 面板显示 60fps 稳定
- [ ] Flutter DevTools Memory 面板显示内存增量 < 5MB

## PRD 错误修正验证

- [x] PRD 4.1 表中"酷狗增强 LRC（行内 `<mm:ss.xx>` 逐字时间戳）"已被替换为"KRC 明文（`[ms,ms]`+`<ms,ms,0>`）"（spec.md L272-284、L326-329）
- [x] PRD 4.1 表中 TTML 行已移除（spec.md L45、L316-319）
- [x] PRD 6 节架构图已扩展为包含模糊背景、手势、控制栏的整体播放页架构（spec.md L286-310）
- [x] PRD 范围已扩展为"1:1 复刻 Apple Music 播放页 + 手势交互"，不只是歌词渲染（spec.md L32-34）

## 范围边界验证（不做项）

- [x] 未引入 TTML 解析（无数据源） — Grep 确认 `lib/` 下无 `TTML`/`ttml` 引用（仅 Node 端 bundle 字符串匹配）
- [x] 未实现拖动歌词跳转（用户只要点击跳转） — `AppleLyricsView` 仅实现 `onTapDown`/`onTapUp` 点击跳转，无拖动跳转逻辑
- [x] 未实现长按菜单
- [x] 未做 Windows / Web 端
- [x] 未改动 md3Music 桌面歌词
- [x] 未写 golden test（仅单元测试 + 预览页）
- [x] 未引入新依赖（无 `xml` 包、无 WebView、无 JS Bridge） — Grep 确认 `lib/` 下无 `package:xml` / `WebView` 引用
