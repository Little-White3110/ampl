# Tasks

- [x] Task 1: 添加 Lyricon Provider SDK 依赖与 Manifest 元数据
  - [x] SubTask 1.1: 在 `md3Music/android/app/build.gradle.kts` 的 dependencies 中添加 `implementation("io.github.proify.lyricon:provider:0.1.70")`
  - [x] SubTask 1.2: 在 `md3Music/android/app/src/main/AndroidManifest.xml` 的 `<application>` 节点添加 `lyricon_module=true`、`lyricon_module_author=md3music`、`lyricon_module_description=MD3Music Lyricon Provider` 三个 meta-data
  - [x] SubTask 1.3: 创建或编辑 `md3Music/android/app/src/main/res/values/arrays.xml`，新增 `lyricon_module_tags` 字符串数组，包含 `$syllable` 和 `$translation` 两个 item
  - [x] SubTask 1.4: 在 AndroidManifest.xml 添加 `lyricon_module_tags` meta-data 引用上述数组资源
  - [x] SubTask 1.5: 执行 `flutter build apk --debug` 验证 Gradle 同步与编译通过（跳过，由后续步骤统一验证）

- [x] Task 2: 在 AudioPlaybackService 中集成 LyriconProvider 生命周期
  - [x] SubTask 2.1: 在 `AudioPlaybackService.kt` 添加 `LyriconProvider` 私有字段
  - [x] SubTask 2.2: 在 `onCreate()` 中调用 `LyriconFactory.createProvider(context)` 创建实例，设置 `autoSync = true`
  - [x] SubTask 2.3: 注册 ConnectionListener，把 `onConnected/onReconnected/onDisconnected/onConnectTimeout` 通过 MethodChannel `com.md3music.md3music/lyricon` 反向回调到 Dart
  - [x] SubTask 2.4: 在 `onDestroy()` 中调用 `provider.unregister()`（若已注册）+ `provider.destroy()`
  - [x] SubTask 2.5: 在 `showNotification()` 中 `mediaSession.setPlaybackState()` 调用后追加 `provider.player.setPlaybackState(playbackState)` 同步给 Lyricon

- [x] Task 3: 在 MainActivity 注册 lyricon MethodChannel handler
  - [x] SubTask 3.1: 在 `MainActivity.configureFlutterEngine()` 中创建 `MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.md3music.md3music/lyricon")`
  - [x] SubTask 3.2: 实现 handler 分发以下方法到 AudioPlaybackService 的 Provider 实例：`setEnabled` / `setSong` / `sendText` / `setPosition` / `setPlaybackState` / `seekTo` / `setDisplayTranslation` / `setDisplayRoma`
  - [x] SubTask 3.3: `setEnabled(true)` 调用 `provider.register()`，`setEnabled(false)` 调用 `provider.unregister()`
  - [x] SubTask 3.4: `setSong` 参数为 Map 时构造 `Song` + `RichLyricLine` + `LyricWord` 对象，参数为 null 时调用 `provider.player.setSong(null)`
  - [x] SubTask 3.5: AudioPlaybackService 暴露 Provider 实例的访问方法（companion 字段或 getter），供 MainActivity handler 调用

- [x] Task 4: 新建 Dart 侧 LyriconProviderService
  - [x] SubTask 4.1: 创建文件 `md3Music/lib/core/services/lyricon_provider_service.dart`，仿 `DesktopLyricService` 单例结构
  - [x] SubTask 4.2: 持有 `MethodChannel('com.md3music.md3music/lyricon')`，设置反向回调 handler 接收 `onConnectionStateChanged`
  - [x] SubTask 4.3: 暴露 `setEnabled(bool)` / `setSong(LyricLine list, song meta)` / `seekTo(int ms)` / `setPosition(int ms)` / `setDisplayTranslation(bool)` / `setDisplayRoma(bool)` 方法
  - [x] SubTask 4.4: 把 `apple_lyrics/models/lyric_line.dart` 的 `LyricLine` / `LyricWord` 转换为 Map 结构（含 `begin` / `end` / `text` / `words` 字段），通过 channel `setSong` 推送
  - [x] SubTask 4.5: 维护 `ConnectionState` 枚举（disabled / connecting / connected / disconnected / timeout），通过 `addListener` 通知设置页刷新

- [x] Task 5: 在 SettingsRepository 新增 Lyricon 持久化字段
  - [x] SubTask 5.1: 在 `md3Music/lib/data/repositories/settings_repository.dart` 新增 `getLyriconEnabled()` / `setLyriconEnabled(bool)` 方法（默认 false）
  - [x] SubTask 5.2: 新增 `getLyriconDisplayTranslation()` / `setLyriconDisplayTranslation(bool)` 方法（默认 true）
  - [x] SubTask 5.3: 新增 `getLyriconDisplayRoma()` / `setLyriconDisplayRoma(bool)` 方法（默认 false）
  - [x] SubTask 5.4: 持久化 key 使用 SharedPreferences 已有命名规范（如 `lyricon_enabled` / `lyricon_display_translation` / `lyricon_display_roma`）

- [x] Task 6: 在设置页新增 Lyricon 开关与状态提示
  - [x] SubTask 6.1: 在 `md3Music/lib/modules/settings/settings_page.dart` 新增一个 SwitchListTile「Lyricon 词幕推送」
  - [x] SubTask 6.2: 开关下方用小字 Text 显示当前 `LyriconProviderService` 的连接状态：未启用 / 连接中... / 已连接 / 已断开 / 连接超时，请检查 Lyricon / LSPosed 配置
  - [x] SubTask 6.3: 开关变化时调用 `LyriconProviderService.setEnabled(bool)` 并持久化到 SettingsRepository
  - [x] SubTask 6.4: 进入设置页时通过 `addListener` 订阅状态变化刷新 UI，离开时 `removeListener`
  - [x] SubTask 6.5: 在 Lyricon 开关下方新增两个次级 SwitchListTile「翻译歌词」「罗马音」，调用 `setDisplayTranslation` / `setDisplayRoma`

- [x] Task 7: 在 PlayerProvider 与 main.dart 接入 Lyricon 钩子
  - [x] SubTask 7.1: 在 `md3Music/lib/main.dart` 启动时调用 `LyriconProviderService.instance.initialize()`，注册反向回调
  - [x] SubTask 7.2: 在 `PlayerProvider.seekTo(pos)` 路径上追加 `LyriconProviderService.instance.seekTo(pos.inMilliseconds)`（仅在 enabled 时实际推送）
  - [x] SubTask 7.3: 在 PlayerProvider 切歌回调中调用 `LyriconProviderService.instance.onSongChanged(song, lyricLines)`，触发 setSong 推送
  - [x] SubTask 7.4: 复用 `apple_lyrics/parsers/lyric_parser_chain.dart` 的解析结果，不重新解析
  - [x] SubTask 7.5: Lyricon 推送节流：进度同步不超过 500ms 一次，setSong 仅在切歌时调用

- [x] Task 8: 验证与现有桌面歌词并存不冲突
  - [x] SubTask 8.1: 同时开启自研桌面歌词（FloatingLyricService）与 Lyricon 推送，确认两者独立工作
  - [x] SubTask 8.2: 关闭 Lyricon 推送后，自研浮窗不受影响
  - [x] SubTask 8.3: 关闭自研浮窗后，Lyricon 推送不受影响
  - [x] SubTask 8.4: Android 8.1 以下设备测试 Provider SDK 空实现不崩溃

- [x] Task 9: 编写 LYRICON_INTEGRATION.md 集成文档
  - [x] SubTask 9.1: 在项目根目录新建 `LYRICON_INTEGRATION.md`
  - [x] SubTask 9.2: 编写「用户使用说明」部分：Lyricon 介绍、为何要装、Lyricon 应用安装、LSPosed 作用域配置（勾选 md3music）、LocalCentralService 本地测试步骤、FAQ（注册后没显示歌词怎么办、翻译不显示怎么办、罗马音不显示怎么办）
  - [x] SubTask 9.3: 编写「开发者集成文档」部分：架构设计图（Dart → MethodChannel → Kotlin → LyriconProvider → 中心服务）、Provider 生命周期时序、MethodChannel 协议表、常见故障定位（连接超时 / 中心服务未运行 / LSPosed 作用域缺失）
  - [x] SubTask 9.4: 在文档明确说明：Provider 应用本身不需要 LSPosed 挂载，需要 LSPosed 激活的是 Lyricon 应用本身（中心服务提供端），并把 md3music 加入 Lyricon 的 LSPosed 作用域

# Task Dependencies

- Task 2, Task 3 依赖 Task 1（需要 SDK 依赖先就位）
- Task 4 依赖 Task 3（需要 MethodChannel handler 已注册）
- Task 5 独立，可与 Task 2/3/4 并行
- Task 6 依赖 Task 4 + Task 5（需要 Service 和持久化都就位）
- Task 7 依赖 Task 4（需要 Dart Service 已实现）
- Task 8 依赖 Task 1-7 全部完成
- Task 9 依赖 Task 1-7 全部完成（文档需要反映最终实现）
