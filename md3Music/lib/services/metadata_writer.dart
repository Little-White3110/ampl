import 'package:flutter/services.dart';

/// 元数据写入客户端：通过 MethodChannel 调用原生 JAudioTagger，
/// 将标题/艺术家/专辑/封面/歌词嵌入已下载的音频文件。
///
/// 原生端实现见 [MetadataWriterPlugin.kt]，channel 名为
/// "com.md3music.md3music/metadata"。
///
/// 调用方应在下载完成后 fire-and-forget 调用 [writeMetadata]：
/// 失败返回 false，不阻断下载流程（用户已能播放文件，只是缺元数据）。
class MetadataWriter {
  static const MethodChannel _channel =
      MethodChannel('com.md3music.md3music/metadata');

  /// 将元数据写入 [filePath] 指向的音频文件。
  ///
  /// - [filePath]：音频文件绝对路径（必填）
  /// - [title]：歌曲标题
  /// - [artist]：艺术家
  /// - [album]：专辑名
  /// - [artworkPath]：封面图本地路径（可选；传入则嵌入 APIC / METADATA_BLOCK_PICTURE）
  /// - [lyrics]：LRC 文本（可选；传入则嵌入 USLT / LYRICS）
  ///
  /// 返回 true 表示写入成功；false 表示失败（原生抛异常或返回 error）。
  /// 任何异常都被吞掉返回 false，调用方不需要 try/catch。
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
      // 原生端写标签失败（文件不存在 / 格式不支持 / IO 错误等）
      return false;
    } catch (_) {
      // MethodChannel 通信异常
      return false;
    }
  }
}
