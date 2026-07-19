# Lyricon 词幕集成文档

本文件分为两部分：上半部分面向终端用户，介绍 Lyricon 是什么、如何安装、如何与 md3music 配合使用；下半部分面向项目开发者，介绍 Provider 的架构设计、生命周期、MethodChannel 协议与故障定位。

---

## 上半部分：用户使用说明

### 1. Lyricon 是什么

Lyricon 是一个独立的第三方词幕应用，能够在系统层渲染桌面歌词浮窗，支持多播放器同时推送歌词数据。md3music 通过 Lyricon Provider SDK 把当前歌曲、逐字歌词、播放进度实时推送到 Lyricon，再由 Lyricon 统一绘制桌面词幕。

**主要优势**

- 跨应用统一词幕样式：多个播放器共用同一套词幕外观，无需各自实现浮窗
- 支持逐字动效：基于 KRC 字级时间戳渲染卡拉OK 式逐字高亮
- 支持翻译和罗马音：在主歌词下方展示翻译行或罗马音行
- 系统级渲染：脱离任何播放器窗口，桌面顶层常驻显示

**适用场景**

- 希望脱离播放器自带浮窗、使用更强大词幕功能的用户
- 同时使用多个播放器、希望词幕体验统一化的用户

### 2. 为何要装 Lyricon

md3music 自带 `FloatingLyricService` 悬浮窗歌词，能够独立完成桌面歌词的基础展示。但功能相对受限，主要表现为：

- 不支持跨播放器统一渲染
- 逐字动效较为基础
- 翻译和罗马音展示能力有限

Lyricon 把这些能力集中到独立的词幕应用中维护，提供更丰富的样式和更稳定的桌面渲染。两者使用完全独立的推送通道，可以并存：用户既可以使用 md3music 自带的悬浮窗，也可以同时启用 Lyricon 推送，按需选择。

### 3. 安装 Lyricon 应用

Lyricon 是一个普通 Android 应用，需要从 Lyricon 官方渠道获取（GitHub release 或官网）。

安装完成后，Lyricon 本身作为 LSPosed 模块运行，因此需要先激活 LSPosed 框架才能正常工作。

> **关键澄清**：md3music 作为 Provider（歌词提供端），**本身不需要在 LSPosed 里挂载**。需要 LSPosed 激活的是 Lyricon 应用本身（中心服务提供端）。md3music 只是通过 Lyricon Provider SDK 主动连接到 Lyricon 中心服务，不依赖任何注入式机制。

### 4. LSPosed 作用域配置

要让 Lyricon 中心服务识别 md3music 作为 Provider，需要按以下步骤配置 LSPosed：

**步骤 1**：在 LSPosed 管理器中激活 Lyricon 模块

打开 LSPosed 管理器 → 模块列表 → 找到 Lyricon → 启用模块。

**步骤 2**：在 Lyricon 模块的「作用域」中勾选 md3music

进入 Lyricon 模块详情 → 作用域 → 在应用列表中勾选 `md3music`。这一步让 Lyricon 中心服务能够连接到 md3music 进程提供的 Provider。

**步骤 3**：重启 md3music 进程

完全杀掉 md3music 进程（从最近任务列表划掉，或强制停止），再重新启动。这样 Lyricon 才能识别到新的作用域配置。

**步骤 4**：在 md3music 设置页打开「Lyricon 词幕推送」开关

打开 md3music → 进入设置 → 找到「歌词」区域 → 打开「Lyricon 词幕推送」开关。开关下方会显示当前连接状态，详见下一节。

### 5. LocalCentralService 本地测试（可选）

如果当前设备没有 LSPosed 环境，但仍想验证 Lyricon Provider 接入是否正常，可以使用官方提供的本地中心服务 LocalCentralService 做基础测试。

**下载地址**：<https://github.com/proify/lyricon/releases/tag/localcentral>

**测试步骤**

1. 下载并安装 LocalCentralService APK
2. 打开应用，授予悬浮窗权限
3. 激活服务（应用内会显示服务运行状态）
4. 打开 md3music 设置页，开启「Lyricon 词幕推送」开关
5. 播放任意歌曲，观察 LocalCentralService 浮窗是否显示歌词

> **注意**：LocalCentralService 仅用于测试用途，覆盖默认中心服务包名。正式发布前应删除该配置，使用默认 Lyricon 中心服务。

### 6. 在 md3music 中启用 Lyricon 推送

完整启用流程如下：

1. 打开 md3music → 设置
2. 在「歌词」区域找到「Lyricon 词幕推送」开关
3. 打开开关
4. 观察开关下方的状态文字，确认连接成功

**连接状态文字说明**

| 状态文字 | 含义 | 处理建议 |
|---|---|---|
| 未启用 | 开关关闭 | 打开开关即可 |
| 连接中... | 正在向中心服务发起注册 | 等待几秒，若长时间停留则检查 Lyricon 是否运行 |
| 已连接 | 与中心服务建立连接 | 推送正常 |
| 已断开 | 连接断开（通常因中心服务退出或进程被杀） | 重新打开 Lyricon 应用，必要时重启 md3music |
| 连接超时，请检查 Lyricon / LSPosed 配置 | 注册请求未在超时时间内得到响应 | 检查 Lyricon 是否安装、LSPosed 作用域是否勾选 md3music |

**次级开关**

在主开关下方还有两个次级开关：

- 翻译歌词：开启后，若歌词数据中包含翻译字段，会在主歌词下方显示翻译行
- 罗马音：开启后，若歌词数据中包含罗马音字段，会在主歌词下方显示罗马音行

次级开关仅控制显示状态，是否能实际显示还取决于歌词数据本身是否提供了对应字段。

### 7. 常见问题 FAQ

#### Q1: 打开开关后为什么没有显示歌词？

可能原因：

- Lyricon 中心服务未运行（检查 Lyricon 应用是否已启动）
- LSPosed 作用域未正确配置（确认在 LSPosed 管理器中已勾选 md3music）
- md3music 设置页的「Lyricon 词幕推送」开关未真正打开（确认状态文字不是「未启用」）
- 当前歌曲没有可用的歌词数据
- 当前设备为 Android 8.1 以下，Provider SDK 返回空实现

#### Q2: 翻译歌词为什么不显示？

需要同时满足以下三个条件：

- 歌词数据中提供了翻译字段（部分歌曲没有翻译数据）
- md3music 设置页打开了「翻译歌词」开关
- Lyricon 展示端允许显示翻译

#### Q3: 罗马音为什么不显示？

同翻译歌词，需要同时满足：

- 歌词数据中提供了罗马音字段
- md3music 设置页打开了「罗马音」开关
- Lyricon 展示端允许显示罗马音

#### Q4: 同时开自研桌面歌词和 Lyricon 会冲突吗？

不会冲突。两者使用完全独立的推送通道：

- 自研桌面歌词由 md3music 的 `FloatingLyricService` 直接绘制浮窗
- Lyricon 推送由 Lyricon 应用绘制浮窗

两者可以同时启用。如果想用 Lyricon 完全替代自研浮窗，关闭 md3music 的桌面歌词开关即可。

#### Q5: Android 8.1 以下能用吗？

Lyricon Provider SDK 在 Android 8.1 以下设备返回空实现，调用 `register()` / `setSong()` 等方法为 no-op，不会崩溃但也不会推送任何数据。如果需要使用 Lyricon 词幕，建议升级到 Android 8.1 或以上版本。

#### Q6: 切歌后 Lyricon 没有立刻更新？

切歌时 md3music 会异步拉取歌词并解析，再推送到 Lyricon。在歌词接口较慢或网络较差时可能有数秒延迟，属于正常现象。如果长时间不更新，确认当前歌曲是否实际有可用歌词。

---

## 下半部分：开发者集成文档

### 1. 架构设计

整体架构分两层：Dart 层负责从播放状态和歌词解析结果中提取数据，Kotlin 层负责调用 Lyricon Provider SDK 与中心服务通信。两层通过 MethodChannel `com.md3music.md3music/lyricon` 解耦。

```
┌─────────────────────────────────────────────────┐
│ Dart 层                                          │
│  PlayerProvider ──切歌/seekTo──→ LyriconProvider │
│                                  Service.dart    │
│  SettingsPage ──开关──→ LyriconProviderService   │
└──────────────────┬──────────────────────────────┘
                   │ MethodChannel
                   │ com.md3music.md3music/lyricon
                   ▼
┌─────────────────────────────────────────────────┐
│ Kotlin 层                                        │
│  MainActivity ─handler─→ AudioPlaybackService    │
│                            │                     │
│                            ▼                     │
│                      LyriconProvider             │
│                            │                     │
│                            ▼                     │
│                      Lyricon 中心服务             │
│                      (LSPosed 注入)              │
└─────────────────────────────────────────────────┘
```

**关键设计要点**

- Provider 实例由 `AudioPlaybackService` 持有（companion 静态变量），方便 `MainActivity` 的 MethodChannel handler 直接访问
- Dart 侧 `LyriconProviderService` 为单例，仿 `DesktopLyricService` 结构
- 所有 MethodChannel 调用均 try-catch 静默吞异常，避免桥接失败影响主播放流程
- Provider 在创建时即设置 `autoSync = true`，断线重连后自动同步最近一次缓存状态
- Kotlin → Dart 反向回调（连接状态变化）通过同一通道的 `invokeMethod` 实现

### 2. Provider 生命周期

Provider 的创建、注册、注销、销毁分散在多个生命周期点，下表汇总了所有触发时机：

| 时机 | 动作 | 调用代码 |
|---|---|---|
| `AudioPlaybackService.onCreate()` | 创建 Provider 实例，设 `autoSync = true`，注册 ConnectionListener | `LyriconFactory.createProvider(this)` |
| 用户打开「Lyricon 推送」开关 | 发起注册 | `provider.register()` |
| 用户关闭开关 | 主动断开连接 | `provider.unregister()` |
| `AudioPlaybackService.onDestroy()` | 注销并释放资源 | `provider.unregister()` + `provider.destroy()` |
| 切歌 | Dart 侧通过 `onSongChanged` 推送 Song 给 Kotlin | `provider.player.setSong(song)` |
| 用户拖动进度条 | Dart 侧 `seekTo(ms)` → Kotlin 调 SDK | `provider.player.seekTo(ms)` |
| `PlaybackStateCompat` 变化 | `AudioPlaybackService.showNotification` 中同步 | `provider.player.setPlaybackState(state)` |

**ConnectionListener 转发机制**

`AudioPlaybackService` 在创建 Provider 时即注册 `ConnectionListener`，四个回调（`onConnected` / `onReconnected` / `onDisconnected` / `onConnectTimeout`）会通过 `lyriconChannel?.invokeMethod("onConnectionStateChanged", ...)` 反向回调到 Dart 侧，由 `LyriconProviderService._onConnectionStateChanged` 切换内部状态枚举并通知 UI 刷新。

### 3. MethodChannel 协议

通道名：`com.md3music.md3music/lyricon`

#### 3.1 Dart → Kotlin 调用

| 方法 | 参数 | 说明 |
|---|---|---|
| `setEnabled` | `{bool enabled}` | 启用 / 禁用 Provider（内部调用 `register()` / `unregister()`） |
| `setSong` | `{Map? song}` | 推送结构化歌曲，`null` 表示清空 |
| `sendText` | `{String text}` | 推送纯文本（无时间轴） |
| `setPosition` | `{int positionMs}` | 同步播放位置（毫秒） |
| `setPlaybackState` | `{int state, int position, double speed}` | 同步 PlaybackState（state 为 `PlaybackStateCompat` 状态码） |
| `seekTo` | `{int positionMs}` | 用户主动跳转到指定位置 |
| `setDisplayTranslation` | `{bool enabled}` | 翻译开关 |
| `setDisplayRoma` | `{bool enabled}` | 罗马音开关 |

#### 3.2 Kotlin → Dart 回调

| 方法 | 参数 | 说明 |
|---|---|---|
| `onConnectionStateChanged` | `String state` | 连接状态变化，取值：`connected` / `reconnected` / `disconnected` / `timeout` |

#### 3.3 Song Map 结构

`setSong` 方法的 `song` 参数为一个 Map，结构如下：

```json
{
  "id": "song-id",
  "name": "普通朋友",
  "artist": "陶喆",
  "duration": 2000,
  "lyrics": [
    {
      "begin": 0,
      "end": 1000,
      "text": "我无法只是普通朋友",
      "translation": "I can't just be a normal friend",
      "secondary": null,
      "words": [
        {"text": "我", "begin": 0, "end": 200},
        {"text": "无法", "begin": 200, "end": 400}
      ]
    }
  ]
}
```

**字段映射说明**

- `Song.title` → Map 的 `name` 字段（与 Kotlin SDK 的 `Song.name` 对齐）
- `Song.duration` 是 `Duration` 类型，需要 `inMilliseconds` 转 int
- `LyricLine.startTime` / `endTime` 均为毫秒 int
- `LyricWord` 没有独立的 `endTime` getter，由 `startTime + duration` 计算得到
- `LyricLine.translation` 是 `String?`，原样透传，无翻译时为 `null`
- 行级 LRC 歌词 `words` 为空数组；KRC 逐字歌词 `words` 包含字级时间戳

### 4. 故障定位

#### 问题 1: 连接超时（状态文字显示「连接超时，请检查 Lyricon / LSPosed 配置」）

排查顺序：

1. 确认 Lyricon 应用已安装并启动
2. 确认 LSPosed 已激活 Lyricon 模块
3. 确认 LSPosed 作用域勾选了 md3music
4. 确认 md3music 进程已重启（作用域变更后必须重启进程）
5. 如果使用 LocalCentralService 测试，确认 LocalCentralService 已启动并授予悬浮窗权限

#### 问题 2: 中心服务未运行

通过 logcat 过滤 `Lyricon` 关键字查看 SDK 抛出的错误：

```bash
adb logcat | grep Lyricon
```

确认 Lyricon 应用进程存活，必要时重启 Lyricon 应用。

#### 问题 3: LSPosed 作用域缺失

按以下路径检查：

```
LSPosed 管理器 → 模块 → Lyricon → 作用域 → 勾选 md3music
```

修改后必须重启 md3music 进程（从最近任务列表划掉后重新启动）。

#### 问题 4: 推送数据但中心服务未显示

- 确认 `setSong` 调用的 Song Map 结构完整（特别是 `lyrics` 数组非空，每行 `begin` / `end` 字段正确）
- 确认 `setPlaybackState` 的 `state` 值符合 Android `PlaybackStateCompat` 状态约定（如 `STATE_PLAYING = 3`、`STATE_PAUSED = 2`）
- 确认 Lyricon 展示端允许显示翻译 / 罗马音（如果开了次级开关但 Lyricon 端禁用，仍不会显示）

#### 问题 5: Android 8.1 以下崩溃

Provider SDK 在 Android 8.1 以下应自动返回空实现，不崩溃。如果发生崩溃，按以下方向排查：

- 检查 `AudioPlaybackService.onCreate()` 中 `LyriconFactory.createProvider(this)` 是否被 try-catch 包裹（当前实现已包裹）
- 检查 ConnectionListener 注册是否被独立的 try-catch 包裹（当前实现已包裹）
- 确认 SDK 版本为 `0.1.70` 或以上

### 5. 关键文件清单

下表汇总了 Lyricon Provider 集成涉及的所有文件及其职责：

| 文件 | 职责 |
|---|---|
| `md3Music/android/app/build.gradle.kts` | 声明 Lyricon Provider SDK 依赖 `io.github.proify.lyricon:provider:0.1.70` |
| `md3Music/android/app/src/main/AndroidManifest.xml` | 声明 `lyricon_module` / `lyricon_module_author` / `lyricon_module_description` / `lyricon_module_tags` 元数据 |
| `md3Music/android/app/src/main/res/values/arrays.xml` | 声明 `lyricon_module_tags` 资源数组（`$syllable` + `$translation`） |
| `md3Music/android/app/src/main/kotlin/com/md3music/md3music/AudioPlaybackService.kt` | Provider 实例持有、生命周期管理、`buildLyriconSong` 工具方法、ConnectionListener 转发 |
| `md3Music/android/app/src/main/kotlin/com/md3music/md3music/MainActivity.kt` | 注册 `com.md3music.md3music/lyricon` MethodChannel handler，分发 8 个方法 |
| `md3Music/lib/core/services/lyricon_provider_service.dart` | Dart 侧 `LyriconProviderService` 单例，提供 `setEnabled` / `setSong` / `seekTo` 等方法 |
| `md3Music/lib/modules/settings/settings_page.dart` | Lyricon 主开关、翻译开关、罗马音开关、连接状态文字 UI |
| `md3Music/lib/data/repositories/settings_repository.dart` | 持久化 `lyricon_enabled` / `lyricon_display_translation` / `lyricon_display_roma` 三个偏好 |
| `md3Music/lib/providers/player_provider.dart` | 切歌钩子（`_handleLyriconSongChange`）、`seekTo` 钩子转发到 Lyricon |
| `md3Music/lib/main.dart` | 启动时调用 `LyriconProviderService.instance.initialize()` 注册反向回调 handler |

### 6. AndroidManifest 配置示例

`AndroidManifest.xml` 的 `<application>` 节点中需要声明以下 meta-data：

```xml
<meta-data android:name="lyricon_module" android:value="true" />
<meta-data android:name="lyricon_module_author" android:value="md3music" />
<meta-data android:name="lyricon_module_description" android:value="MD3Music Lyricon Provider" />
<meta-data android:name="lyricon_module_tags" android:resource="@array/lyricon_module_tags" />
```

`res/values/arrays.xml` 中声明能力标签：

```xml
<string-array name="lyricon_module_tags">
    <item>$syllable</item>
    <item>$translation</item>
</string-array>
```

| 标签 | 含义 |
|---|---|
| `$syllable` | 支持逐字 / 动态歌词 |
| `$translation` | 支持歌词翻译显示 |

标签仅声明能力，不会自动启用对应功能，实际是否逐字 / 是否显示翻译取决于歌词数据和运行时开关。

### 7. Gradle 依赖

`md3Music/android/app/build.gradle.kts` 的 `dependencies` 块新增：

```kotlin
implementation("io.github.proify.lyricon:provider:0.1.70")
```

当前 md3music 的 `compileSdk = 36`、`targetSdk = 35`、`minSdk` 由 Flutter 默认值决定（一般为 21）。Provider SDK 在 Android 8.1（API 27）以下返回空实现，不会崩溃。

### 8. Provider 创建与销毁示例

`AudioPlaybackService.onCreate()` 中的关键代码（简化版）：

```kotlin
lyriconProvider = try {
    LyriconFactory.createProvider(this).apply {
        autoSync = true
        try {
            service.addConnectionListener {
                onConnected { _ ->
                    lyriconChannel?.invokeMethod("onConnectionStateChanged", "connected")
                }
                onReconnected { _ ->
                    lyriconChannel?.invokeMethod("onConnectionStateChanged", "reconnected")
                }
                onDisconnected { _ ->
                    lyriconChannel?.invokeMethod("onConnectionStateChanged", "disconnected")
                }
                onConnectTimeout { _ ->
                    lyriconChannel?.invokeMethod("onConnectionStateChanged", "timeout")
                }
            }
        } catch (_: Exception) {}
    }
} catch (_: Exception) {
    null
}
```

`AudioPlaybackService.onDestroy()` 中释放资源：

```kotlin
try { lyriconProvider?.unregister() } catch (_: Exception) {}
try { lyriconProvider?.destroy() } catch (_: Exception) {}
lyriconProvider = null
```

所有 SDK 调用都包裹 try-catch，避免 SDK 在异常环境下抛错导致服务崩溃。

### 9. Dart 侧使用示例

初始化（在 `main.dart` 中）：

```dart
LyriconProviderService.instance.initialize();
```

开关切换（设置页）：

```dart
LyriconProviderService.instance.setEnabled(value);
```

切歌推送（`PlayerProvider` 中）：

```dart
// 通过 addListener 监听自身 notifyListeners 检测切歌
void _handleLyriconSongChange() {
  if (!LyriconProviderService.instance.enabled) return;
  final song = _currentSong;
  if (song?.id == _lastLyriconSong?.id) return;
  _lastLyriconSong = song;
  _pushLyriconSongChange(song);
}
```

进度条拖动：

```dart
if (LyriconProviderService.instance.enabled) {
  LyriconProviderService.instance.seekTo(position.inMilliseconds);
}
```

### 10. 与自研桌面歌词并存

`FloatingLyricService`（自研浮窗）和 `LyriconProviderService`（Lyricon 推送）使用完全独立的通道：

- 自研浮窗通过 `com.md3music.md3music/floating_lyric` 通道
- Lyricon 推送通过 `com.md3music.md3music/lyricon` 通道

两者互不感知，可以同时启用。若用户希望用 Lyricon 替代自研浮窗，只需关闭自研桌面歌词开关即可，Lyricon 推送不受影响。
