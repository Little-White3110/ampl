# 下载服务优化方案

> 分支：`feature/download-service-optimization`（基于 `main`）
>
> 目标：
> 1. 自定义下载目录（默认系统 Downloads 目录 `/storage/emulated/0/Download/MD3Music`，设置页可改）
> 2. 下载歌曲内嵌元数据（标题/艺术家/专辑/封面/歌词）—— 通过原生 MethodChannel + JAudioTagger 写入 ID3v2 / FLAC 标签
> 3. CI 在 feature 分支推送时触发，便于用户拉 APK 测试

---

## 一、当前状态分析

| 问题 | 现状文件 | 缺陷 |
|---|---|---|
| 下载目录硬编码 | [download_manager.dart:21-39](file:///c:/Users/32732/Desktop/TRAE%20SOLO/ampl/md3Music/lib/services/download_manager.dart#L21-L39) | 写死 `<external>/Music/MD3Music`，用户不可改 |
| 文件名用 hash | [download_manager.dart:56](file:///c:/Users/32732/Desktop/TRAE%20SOLO/ampl/md3Music/lib/services/download_manager.dart#L56) | `${songId}.${ext}`，文件管理器不可读 |
| 无元数据嵌入 | [download_manager.dart:59-71](file:///c:/Users/32732/Desktop/TRAE%20SOLO/ampl/md3Music/lib/services/download_manager.dart#L59-L71) | dio 直接落盘，无标签写入 |
| 设置页无下载项 | [settings_page.dart:520-535](file:///c:/Users/32732/Desktop/TRAE%20SOLO/ampl/md3Music/lib/modules/settings/settings_page.dart#L520-L535) | 缓存 section 只有清缓存 + 数据迁移 |
| Manifest 缺权限 | [AndroidManifest.xml:1-15](file:///c:/Users/32732/Desktop/TRAE%20SOLO/ampl/md3Music/android/app/src/main/AndroidManifest.xml#L1-L15) | 无 `MANAGE_EXTERNAL_STORAGE`，写系统 Downloads 必失败 |
| 缺 ID3 写入库 | [app/build.gradle.kts:60-65](file:///c:/Users/32732/Desktop/TRAE%20SOLO/ampl/md3Music/android/app/build.gradle.kts#L60-L65) | 仅 media/core-ktx/lyricon，无 JAudioTagger |
| CI 不触发分支 | [ci.yml:3-9](file:///c:/Users/32732/Desktop/TRAE%20SOLO/ampl/.github/workflows/ci.yml#L3-L9) | `push.branches: [main]`，feature 分支推送不跑 |
| DownloadTask 无 album | [download_task.dart:3-24](file:///c:/Users/32732/Desktop/TRAE%20SOLO/ampl/md3Music/lib/data/models/download_task.dart#L3-L24) | 只有 title/artist/artworkUri，无 album 字段 |

---

## 二、决策记录（grill-me 质询结论）

| 决策点 | 选择 | 理由 |
|---|---|---|
| 下载目录类型 | **B. 系统 Downloads** `/storage/emulated/0/Download/MD3Music/` | 用户明确要"系统下载目录"，需新增 MANAGE_EXTERNAL_STORAGE |
| 元数据嵌入实现 | **B. 原生 MethodChannel + JAudioTagger** | 支持 MP3 ID3v2 + FLAC VorbisComment 全格式 |
| JAudioTagger 来源 | **B. JitPack `com.github.AdrienPoupa:jaudiotagger:1.0.1`** | 社区 Android 适配分叉，2021 更新，scoped storage 兼容性最佳 |
| 文件命名 | **B. 可读名** `${artist} - ${title}.${ext}` | 文件管理器可读，需过滤非法字符 + 同名加序号 |
| 权限请求时机 | **B. 首次下载时检查** | 在 `downloadSong` 调用前检查；用户拒绝则提示去设置开启 |
| CI 触发 | **B. 改 ci.yml 加分支** | 在 `push.branches` 追加 `feature/download-service-optimization`，PR 也触发 |
| 设置页 | 新增"下载" section，可改下载目录 | 用户补充要求"下载地址在设置页面要能够允许自定义" |

---

## 三、具体改动

### 1. 新建分支

```bash
git checkout -b feature/download-service-optimization
```

### 2. Android 权限（AndroidManifest.xml）

**文件**：[md3Music/android/app/src/main/AndroidManifest.xml](file:///c:/Users/32732/Desktop/TRAE%20SOLO/ampl/md3Music/android/app/src/main/AndroidManifest.xml)

在 `</application>` 之前补一句 manifest 内的权限（已有 INTERNET/READ_MEDIA_AUDIO 等，缺 MANAGE_EXTERNAL_STORAGE）：

```xml
<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"
    tools:ignore="ScopedStorage" />
```

并在 `<manifest>` 标签补 `xmlns:tools="http://schemas.android.com/tools"`。

### 3. Gradle 依赖（JitPack + JAudioTagger）

**文件 A**：[md3Music/android/build.gradle.kts](file:///c:/Users/32732/Desktop/TRAE%20SOLO/ampl/md3Music/android/build.gradle.kts)

`allprojects.repositories` 内追加 JitPack：

```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }   // 新增：JAudioTagger 分叉来源
    }
}
```

**文件 B**：[md3Music/android/app/build.gradle.kts](file:///c:/Users/32732/Desktop/TRAE%20SOLO/ampl/md3Music/android/app/build.gradle.kts)

`dependencies` 块追加：

```kotlin
implementation("com.github.AdrienPoupa:jaudiotagger:1.0.1")
```

### 4. 原生 Kotlin：MetadataWriter MethodChannel

**新文件**：`md3Music/android/app/src/main/kotlin/com/md3music/md3music/MetadataWriterPlugin.kt`

实现 MethodChannel `"com.md3music.md3music/metadata"` 的 `writeMetadata` 方法：

```kotlin
// 关键逻辑示意（非最终代码）：
fun onMethodCall(call, result) {
  if (call.method == "writeMetadata") {
    val filePath = call.argument<String>("filePath")!!
    val title    = call.argument<String>("title") ?: ""
    val artist   = call.argument<String>("artist") ?: ""
    val album    = call.argument<String>("album") ?: ""
    val artworkPath = call.argument<String>("artworkPath")  // 可空
    val lyrics   = call.argument<String>("lyrics")          // 可空
    try {
      val audioFile = AudioFileIO.read(File(filePath))
      val tag = audioFile.tagOrCreateAndSetDefault
      tag.setField(FieldKey.TITLE, title)
      tag.setField(FieldKey.ARTIST, artist)
      tag.setField(FieldKey.ALBUM, album)
      if (artworkPath != null) {
        val art = ArtworkFactory.createArtworkFromFile(File(artworkPath))
        tag.setField(FieldKey.COVER_ART, art)
      }
      if (lyrics != null && lyrics.isNotEmpty()) {
        tag.setField(FieldKey.LYRICS, lyrics)
      }
      audioFile.commit()
      result.success(true)
    } catch (e: Exception) {
      result.error("WRITE_FAILED", e.message, null)
    }
  }
}
```

**文件**：[MainActivity.kt](file:///c:/Users/32732/Desktop/TRAE%20SOLO/ampl/md3Music/android/app/src/main/kotlin/com/md3music/md3music/MainActivity.kt)

在 `configureFlutterEngine` 末尾注册该 channel：

```kotlin
MetadataWriterPlugin().register(flutterEngine, context)
```

### 5. Dart 端：MetadataWriter 客户端

**新文件**：`md3Music/lib/services/metadata_writer.dart`

```dart
// 关键逻辑示意：
class MetadataWriter {
  static const _channel = MethodChannel('com.md3music.md3music/metadata');

  /// 将元数据写入已下载的音频文件。
  /// 返回 true 表示成功；失败时返回 false（调用方决定是否提示用户）。
  static Future<bool> writeMetadata({
    required String filePath,
    required String title,
    required String artist,
    required String album,
    String? artworkPath,
    String? lyrics,
  }) async {
    try {
      final r = await _channel.invokeMethod<bool>('writeMetadata', {
        'filePath': filePath,
        'title': title,
        'artist': artist,
        'album': album,
        if (artworkPath != null) 'artworkPath': artworkPath,
        if (lyrics != null) 'lyrics': lyrics,
      });
      return r ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }
}
```

### 6. DownloadTask 模型扩展

**文件**：[download_task.dart](file:///c:/Users/32732/Desktop/TRAE%20SOLO/ampl/md3Music/lib/data/models/download_task.dart)

新增 `album` 字段（String?），同步 `copyWith` / `toJson` / `fromJson`。这样元数据写入时能拿到专辑名。

### 7. SettingsRepository 新增下载目录持久化

**文件**：[settings_repository.dart](file:///c:/Users/32732/Desktop/TRAE%20SOLO/ampl/md3Music/lib/data/repositories/settings_repository.dart)

新增：

```dart
static const _keyDownloadDir = 'settings_download_dir';

Future<String> getDownloadDir() async {
  final prefs = await SharedPreferences.getInstance();
  // 默认系统 Downloads 下的 MD3Music 子目录，避免污染整个 Download
  return prefs.getString(_keyDownloadDir) ??
      '/storage/emulated/0/Download/MD3Music';
}

Future<void> setDownloadDir(String path) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_keyDownloadDir, path);
}
```

### 8. DownloadManager 改造

**文件**：[download_manager.dart](file:///c:/Users/32732/Desktop/TRAE%20SOLO/ampl/md3Music/lib/services/download_manager.dart)

**改造点：**

1. `_downloadDir` 改为接受参数（由 provider 传入从 settings 读取的目录），不再硬编码。
2. 文件名生成：新增 `_sanitizeFileName(artist)` + `_sanitizeFileName(title)` 过滤 `\ / : * ? " < > |`，拼成 `${artist} - ${title}.${ext}`；同名追加 ` (2)`、` (3)` 序号。
3. `deleteFile` 同步改造：按新命名规则在指定目录下查找并删除；兼容旧 hash 命名（先尝试新规则，再 fallback 旧的 `${songId}.${ext}`）。
4. download 接受 downloadDir 参数。

```dart
Future<String> _buildFilePath(String dir, DownloadTask task) async {
  final ext = _getExtFromUrl(task.downloadUrl);
  final safeArtist = _sanitize(task.artist);
  final safeTitle = _sanitize(task.title);
  var name = '$safeArtist - $safeTitle.$ext';
  var path = '$dir/$name';
  var i = 2;
  while (await File(path).exists()) {
    name = '$safeArtist - $safeTitle ($i).$ext';
    path = '$dir/$name';
    i++;
  }
  return path;
}

String _sanitize(String s) {
  // 过滤文件系统非法字符，并 trim 空白
  return s
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
```

### 9. DownloadsProvider 改造（编排元数据嵌入）

**文件**：[downloads_provider.dart](file:///c:/Users/32732/Desktop/TRAE%20SOLO/ampl/md3Music/lib/providers/downloads_provider.dart)

**关键变化：**

1. `downloadSong(song)` 入口先调用 `requestStoragePermission()`，未授权时提示用户去设置。
2. 构造 DownloadTask 时补 `album: song.album`。
3. 从 settings 读取下载目录，传给 DownloadManager.download(task, downloadDir)。
4. 监听下载完成事件，下载完成后**并行**：
   - 若 `artworkUri` 非空：用 dio 下载封面图到临时文件 `temp/${songId}_art.jpg`
   - 调用 `KugouApiClient().getLyric(song.id, songName: song.title)` 拉取歌词（失败容忍）
5. 调用 `MetadataWriter.writeMetadata(filePath, title, artist, album, artworkPath, lyrics)` 写入。
6. 写入完成后删除临时封面文件。
7. 元数据写入失败不阻断下载完成状态（用户已经能播放），仅 console warning。

```dart
// 伪代码：
void _onTaskUpdate(DownloadTask task) {
  // ... 现有逻辑 ...
  if (task.status == DownloadStatus.completed) {
    _embedMetadata(task);  // fire and forget
  }
}

Future<void> _embedMetadata(DownloadTask task) async {
  String? artPath;
  try {
    if (task.artworkUri != null) {
      artPath = await _downloadArtwork(task.songId, task.artworkUri!);
    }
    final lyric = await KugouApiClient().getLyric(task.songId, songName: task.title);
    final lyricText = lyric?.displayLrcLyric ?? lyric?.decodedContent;
    await MetadataWriter.writeMetadata(
      filePath: task.localPath!,
      title: task.title,
      artist: task.artist,
      album: task.album ?? '',
      artworkPath: artPath,
      lyrics: lyricText,
    );
  } catch (_) {
    // 写入失败不阻断
  } finally {
    if (artPath != null) {
      try { await File(artPath).delete(); } catch (_) {}
    }
  }
}
```

### 10. 设置页新增"下载" section

**文件**：[settings_page.dart](file:///c:/Users/32732/Desktop/TRAE%20SOLO/ampl/md3Music/lib/modules/settings/settings_page.dart)

在 `_buildCacheSection` 之前插入 `_buildDownloadSection`：

```dart
Widget _buildDownloadSection(ColorScheme cs) {
  return Column(
    children: [
      ListTile(
        leading: const Icon(Icons.download),
        title: const Text('下载目录'),
        subtitle: Text(_downloadDir),  // 从 settings 加载
        trailing: const Icon(Icons.chevron_right),
        onTap: _showDownloadDirDialog,
      ),
    ],
  );
}

void _showDownloadDirDialog() {
  // 弹 AlertDialog + TextField，用户输入新路径
  // 保存后 setState + SettingsRepository.setDownloadDir
}
```

在 `build()` 的 ListView 中：
```
_buildSectionHeader('下载'),
_buildDownloadSection(colorScheme),
const Divider(),
```

### 11. CI 触发分支

**文件**：[.github/workflows/ci.yml](file:///c:/Users/32732/Desktop/TRAE%20SOLO/ampl/.github/workflows/ci.yml)

```yaml
on:
  push:
    branches: [main, 'feature/download-service-optimization']   # 加 feature 分支
    tags: ['v*']
  pull_request:
    branches: [main]
  workflow_dispatch:
    inputs:
      include_x86_64:
        description: '额外构建 x86_64（模拟器用）'
        type: boolean
        required: false
        default: false
```

> 注意：tag 触发的 Release 步骤对 feature 分支无影响（`if: startsWith(github.ref, 'refs/tags/v')` 不命中），不会误发 Release。APK 仍会通过 `actions/upload-artifact` 上传，用户从 Actions 页面下载。

### 12. 推送分支触发 CI

完成上述改动后：

```bash
git add -A
git commit -m "feat(download): custom download dir + metadata embedding + CI trigger"
git push -u origin feature/download-service-optimization
```

CI 自动跑 analyze-and-test + build-apk（arm64-v8a + armeabi-v7a）。用户从 GitHub Actions 页面下载 artifact 测试。

---

## 四、假设与约束

1. **JAudioTagger 在 Android 11+ scoped storage 下能正常写入**：用户已选 MANAGE_EXTERNAL_STORAGE 路径，文件路径在 `/storage/emulated/0/Download/` 下，应用有完整读写权。若部分机型仍失败，MetadataWriter 返回 false 不阻断下载。
2. **歌词取 LRC 明文**：`KugouLyric.displayLrcLyric` 优先于 `decodedContent`。KRC 逐字歌词不嵌入（ID3 USLT 帧只支持 LRC 文本）。
3. **FLAC 嵌入支持**：JAudioTagger 分叉原生支持 FLAC VorbisComment + METADATA_BLOCK_PICTURE，无需额外代码分支。
4. **旧下载迁移**：不做自动迁移。已下载的旧 `${songId}.${ext}` 文件保留在原 `<external>/Music/MD3Music/` 目录，用户可在 DownloadsPage 看到旧任务，手动删除后重新下载走新流程。
5. **下载完成到元数据嵌入有延迟**：可能 1-3 秒（拉歌词 + 写标签），用户播放时元数据可能尚未写入；接受这个权衡。

---

## 五、验证步骤

1. **本地静态检查**：
   - `flutter analyze --no-fatal-infos` 无 error/warning
   - `flutter test` 现有用例全过
2. **CI 流水线**：
   - push feature 分支后，Actions 页面 `analyze-and-test` 绿
   - `build-apk` 两个 ABI 都生成 artifact
3. **真机功能测试**（用户拉 APK 后）：
   - 安装 APK，进入设置 → 下载 → 看到 `/storage/emulated/0/Download/MD3Music` 默认值
   - 修改下载目录为 `/storage/emulated/0/Download`，退出重进设置验证持久化
   - 首次点下载 → 跳转系统设置开启 MANAGE_EXTERNAL_STORAGE
   - 重新点下载 → 下载完成
   - 文件管理器进入 `/storage/emulated/0/Download/MD3Music/`，看到文件名形如 `周杰伦 - 晴天.mp3`
   - 用其他播放器（如系统音乐）打开该文件，验证：
     - 标题显示「晴天」
     - 艺术家显示「周杰伦」
     - 专辑封面正确显示
     - 歌词能逐行同步（LRC 嵌入）
4. **降级验证**：
   - 关闭 MANAGE_EXTERNAL_STORAGE 权限再下载 → 下载失败但 UI 有清晰提示
   - 拉歌词接口失败 → 文件仍可下载完成，只是无歌词（控制台 warning）
   - JAudioTagger 写入失败 → 文件仍可下载完成，只是无标签（控制台 warning）

---

## 六、不在此方案范围内（避免过度设计）

- 不做下载队列优先级 / 并发数控制
- 不做已下载文件的元数据补全工具
- 不做下载目录空间检查
- 不做下载断点续传
- 不修改 DownloadsPage 的 UI（播放/删除按钮逻辑保持不变，只是底层 localPath 指向新目录的新命名文件）
