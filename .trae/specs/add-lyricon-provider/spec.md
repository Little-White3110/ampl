# Lyricon Provider 适配 Spec

## Why

当前 md3Music 已有自研悬浮窗歌词（FloatingLyricService），但无法对接第三方词幕应用（Lyricon）。集成 Lyricon Provider SDK 后，可将歌曲信息、KRC 逐字歌词、播放状态推送到 Lyricon 中心服务，由 Lyricon 在系统层统一渲染桌面词幕。自研浮窗保留原状作为附加输出通道并存。

## What Changes

- 在 `md3Music/android/app/build.gradle.kts` 添加 Lyricon Provider 依赖 `io.github.proify.lyricon:provider:0.1.70`
- 在 `AndroidManifest.xml` 的 `<application>` 节点添加 `lyricon_module` / `lyricon_module_author` / `lyricon_module_description` 元数据
- 在 `res/values/arrays.xml` 新增 `lyricon_module_tags` 数组（`$syllable` + `$translation`）
- 在 `AudioPlaybackService` 中持有 `LyriconProvider` 实例，根据开关状态调用 `register()` / `unregister()` / `destroy()`
- 新增 MethodChannel `com.md3music.md3music/lyricon`，Dart 侧推送结构化歌词数据（Song / RichLyricLine / LyricWord）
- 新增 Dart 侧 `LyriconProviderService`（仿 `DesktopLyricService` 结构），负责从 `apple_lyrics/parsers` 拿解析结果，按播放进度推送当前行/字级时间戳到 Kotlin
- 设置页新增「Lyricon 词幕推送」开关（默认关），下方文字提示连接状态：未启用 / 连接中 / 已连接 / 超时 / 中心服务未安装
- `PlaybackStateCompat` 变化时同步推送给 `provider.player.setPlaybackState(state)`
- 用户拖动进度条时主动调用 `provider.player.seekTo(pos)`
- 项目根新建 `LYRICON_INTEGRATION.md`：上半部分面向用户（Lyricon 是什么 / 如何安装 / LSPosed 作用域配置 / LocalCentralService 本地测试 / FAQ），下半部分面向开发者（架构 / Provider 生命周期 / MethodChannel 协议 / 故障定位）

## Impact

- Affected specs: 无（首次接入 Lyricon）
- Affected code:
  - `md3Music/android/app/build.gradle.kts` — 新增依赖
  - `md3Music/android/app/src/main/AndroidManifest.xml` — 新增 meta-data
  - `md3Music/android/app/src/main/res/values/arrays.xml` — 新增 tags 数组（文件可能不存在，需创建）
  - `md3Music/android/app/src/main/kotlin/com/md3music/md3music/AudioPlaybackService.kt` — 持有 Provider 实例，注册/注销/销毁逻辑
  - `md3Music/android/app/src/main/kotlin/com/md3music/md3music/MainActivity.kt` — 注册新 MethodChannel handler
  - `md3Music/lib/core/services/lyricon_provider_service.dart` — 新建 Dart 服务
  - `md3Music/lib/modules/settings/settings_page.dart` — 新增开关与状态提示
  - `md3Music/lib/data/repositories/settings_repository.dart` — 新增 lyriconEnabled 持久化
  - `md3Music/lib/main.dart` — 启动时初始化 LyriconProviderService
  - `md3Music/lib/providers/player_provider.dart` — 播放状态/seekTo 钩子转发到 Lyricon
  - `LYRICON_INTEGRATION.md` — 新建独立文档

## ADDED Requirements

### Requirement: Lyricon Provider SDK 集成

系统 SHALL 在 Android 原生层集成 Lyricon Provider SDK（`io.github.proify.lyricon:provider:0.1.70`），并在 `AndroidManifest.xml` 中声明模块元数据，使 Lyricon 中心服务能识别本应用为 Provider。

#### Scenario: 依赖与 Manifest 配置完成
- **WHEN** Gradle 同步完成且应用打包成功
- **THEN** APK 中包含 Lyricon Provider SDK 类
- **AND** Manifest 中存在 `lyricon_module=true`、`lyricon_module_author=md3music`、`lyricon_module_description=MD3Music Lyricon Provider`
- **AND** `lyricon_module_tags` 资源数组包含 `$syllable` 和 `$translation`

#### Scenario: Android 8.1 以下空实现
- **WHEN** 应用运行在 Android 8.1 以下设备
- **THEN** Provider SDK 内部返回空实现
- **AND** 应用不崩溃、不报错
- **AND** 调用 `register()` / `setSong()` 等方法为 no-op

### Requirement: Provider 生命周期由 AudioPlaybackService 管理

系统 SHALL 在 `AudioPlaybackService.onCreate()` 中创建 `LyriconProvider` 实例（通过 `LyriconFactory.createProvider(context)`），在 `onDestroy()` 中调用 `provider.destroy()`。`register()` / `unregister()` 由用户开关触发。

#### Scenario: 服务启动时创建 Provider
- **WHEN** `AudioPlaybackService.onCreate()` 被调用
- **THEN** 创建 `LyriconProvider` 实例并持有
- **AND** 添加 ConnectionListener 把状态回调转发到 Dart 侧
- **AND** 设置 `provider.autoSync = true`

#### Scenario: 服务销毁时释放
- **WHEN** `AudioPlaybackService.onDestroy()` 被调用
- **THEN** 调用 `provider.unregister()`（若已注册）
- **AND** 调用 `provider.destroy()` 释放资源

### Requirement: 设置项开关控制启用

系统 SHALL 在设置页新增「Lyricon 词幕推送」开关，默认关闭。开关状态持久化到 `SettingsRepository`。

#### Scenario: 用户首次进入设置页
- **WHEN** 用户打开设置页且未启用过 Lyricon
- **THEN** 开关处于关闭状态
- **AND** 开关下方显示「未启用」

#### Scenario: 用户打开开关
- **WHEN** 用户切换开关到开启
- **THEN** 调用 `provider.register()` 发起注册
- **AND** 开关下方文字变为「连接中...」
- **AND** 持久化 `lyriconEnabled = true`

#### Scenario: 用户关闭开关
- **WHEN** 用户切换开关到关闭
- **THEN** 调用 `provider.unregister()` 断开连接
- **AND** 开关下方文字变为「未启用」
- **AND** 持久化 `lyriconEnabled = false`

### Requirement: 连接状态 UI 反馈

系统 SHALL 在设置页开关下方用文字提示当前连接状态。状态来源于 Provider 的 ConnectionListener 回调。

#### Scenario: 状态流转
- **WHEN** ConnectionListener 触发 `onConnected`
- **THEN** 文字提示变为「已连接」
- **WHEN** ConnectionListener 触发 `onReconnected`
- **THEN** 文字提示变为「已连接」（重连成功）
- **WHEN** ConnectionListener 触发 `onDisconnected`
- **THEN** 文字提示变为「已断开」
- **WHEN** ConnectionListener 触发 `onConnectTimeout`
- **THEN** 文字提示变为「连接超时，请检查 Lyricon / LSPosed 配置」

### Requirement: Dart 推送结构化歌词数据

系统 SHALL 通过新 MethodChannel `com.md3music.md3music/lyricon` 让 Dart 侧推送结构化歌词到 Kotlin。歌词粒度动态选择：有 KRC 字级时间戳时推送 `words`，否则降级为行级。

#### Scenario: 推送 KRC 逐字歌词
- **WHEN** 当前歌曲有 KRC 解析结果且包含 `LyricWord` 列表
- **THEN** Dart 调用 channel `setSong` 方法，参数为序列化的 Song 对象
- **AND** 每行 `RichLyricLine` 包含 `begin`、`end`、`text`、`words`（words 为 LyricWord 数组）
- **AND** Kotlin 收到后调用 `provider.player.setSong(song)`

#### Scenario: 推送 LRC 行级歌词
- **WHEN** 当前歌曲仅有 LRC 行级时间戳
- **THEN** Dart 调用 channel `setSong` 方法
- **AND** 每行 `RichLyricLine` 的 `words` 为空数组
- **AND** Kotlin 收到后调用 `provider.player.setSong(song)`

#### Scenario: 清空歌曲
- **WHEN** 切歌或停止播放
- **THEN** Dart 调用 channel `setSong` 方法，参数为 `null`
- **AND** Kotlin 调用 `provider.player.setSong(null)`

#### Scenario: 复用 apple_lyrics 解析结果
- **WHEN** LyriconProviderService 启用
- **THEN** 复用 `LyricParserChain.parse` 输出的 `LyricLine` / `LyricWord` 模型
- **AND** 转换为 Lyricon SDK 期望的格式（不重新解析歌词源）

### Requirement: 播放状态与进度同步

系统 SHALL 通过两条路径同步播放进度：
1. `PlaybackStateCompat` 变化时调用 `provider.player.setPlaybackState(state)` 兜底
2. 用户拖动进度条时主动调用 `provider.player.seekTo(pos)`

#### Scenario: 播放状态变化
- **WHEN** AudioPlaybackService 中 `mediaSession.setPlaybackState()` 被调用
- **THEN** 同步调用 `provider.player.setPlaybackState(playbackState)`
- **AND** Lyricon 中心服务根据 position+速度+更新时间自行外推进度

#### Scenario: 用户拖动进度条
- **WHEN** Dart 侧检测到用户 seekTo 操作
- **THEN** 通过 lyricon channel 调用 `seekTo` 方法
- **AND** Kotlin 调用 `provider.player.seekTo(positionMs)`
- **AND** 不影响 PlaybackState 同步通道

### Requirement: 应用内 seekTo 与现有播放器集成

系统 SHALL 在 `PlayerProvider` 的 seekTo 路径上挂钩 Lyricon 推送，使应用内进度条拖动能同步到 Lyricon。

#### Scenario: 应用内拖动进度条
- **WHEN** 用户在 full_player 拖动进度条
- **THEN** `PlayerProvider.seekTo(pos)` 调用后
- **AND** LyriconProviderService 同步调用 lyricon channel 的 `seekTo` 方法

### Requirement: MethodChannel 协议

系统 SHALL 在 `com.md3music.md3music/lyricon` 通道上实现以下方法：

| 方法 | 参数 | 说明 |
|---|---|---|
| `setEnabled` | `bool enabled` | 启用/禁用 Provider（调用 register/unregister） |
| `setSong` | `Song? song`（Map 或 null） | 推送结构化歌曲 |
| `sendText` | `String text` | 推送纯文本 |
| `setPosition` | `int positionMs` | 同步播放位置 |
| `setPlaybackState` | `int state, int position, float speed` | 同步 PlaybackState |
| `seekTo` | `int positionMs` | 主动跳转 |
| `setDisplayTranslation` | `bool` | 翻译开关 |
| `setDisplayRoma` | `bool` | 罗马音开关 |

Kotlin → Dart 反向调用：

| 方法 | 参数 | 说明 |
|---|---|---|
| `onConnectionStateChanged` | `String state` | 状态回调：connected/reconnected/disconnected/timeout |

### Requirement: 与现有桌面歌词并存

系统 SHALL 保持 `FloatingLyricService` 及其 Dart 侧 `DesktopLyricService` 原状不变。Lyricon 推送与自研浮窗互不干扰，可同时启用。

#### Scenario: 两者同时启用
- **WHEN** 用户同时开启自研桌面歌词和 Lyricon 推送
- **THEN** 自研浮窗照常显示
- **AND** Lyricon 中心服务照常接收推送
- **AND** 两者各自独立工作，不互相影响

### Requirement: 集成文档

系统 SHALL 在项目根新建 `LYRICON_INTEGRATION.md`，包含「用户使用说明」和「开发者集成文档」两部分。

#### Scenario: 用户使用说明章节
- **WHEN** 用户打开 LYRICON_INTEGRATION.md
- **THEN** 看到 Lyricon 介绍、安装步骤、LSPosed 作用域配置、LocalCentralService 本地测试、常见问题排查

#### Scenario: 开发者集成文档章节
- **WHEN** 开发者打开 LYRICON_INTEGRATION.md
- **THEN** 看到架构设计、Provider 生命周期、MethodChannel 协议表、故障定位指南

## MODIFIED Requirements

### Requirement: AudioPlaybackService 资源管理

在原有 `AudioPlaybackService` 的 `onCreate()` / `onDestroy()` 中追加 Lyricon Provider 实例的创建与销毁逻辑。Provider 创建后默认不调用 `register()`，由 Dart 侧开关触发。

### Requirement: MainActivity MethodChannel 注册

在 `MainActivity.configureFlutterEngine()` 中追加新通道 `com.md3music.md3music/lyricon` 的 `setMethodCallHandler`，分发到 `AudioPlaybackService` 持有的 Provider 实例。

### Requirement: SettingsRepository 持久化项

新增持久化字段：
- `lyriconEnabled: Boolean`（默认 false）
- `lyriconDisplayTranslation: Boolean`（默认 true）
- `lyriconDisplayRoma: Boolean`（默认 false）

## REMOVED Requirements

无。
