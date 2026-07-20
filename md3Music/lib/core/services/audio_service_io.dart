import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();

  factory AudioService() => _instance;

  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();
  final ConcatenatingAudioSource _playlistSource = ConcatenatingAudioSource(children: []);

  /// 标记当前暂停是否由音频焦点被打断导致。
  /// 仅在 interruption begin 时置 true；用户主动 pause/play 时清零。
  /// interruption end 时只有此标记为 true 才自动恢复播放，避免
  /// "用户手动暂停 → 其他 app 短暂占用焦点又释放 → 错误自动恢复播放"。
  bool _pausedByInterruption = false;

  AudioPlayer get player => _player;

  Stream<Duration> get positionStream => _player.positionStream;

  Stream<Duration?> get durationStream => _player.durationStream;

  Stream<bool> get playingStream => _player.playingStream;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Stream<SequenceState?> get sequenceStateStream => _player.sequenceStateStream;

  Stream<double> get speedStream => _player.speedStream;

  bool get playing => _player.playing;

  Duration get position => _player.position;

  Duration? get duration => _player.duration;

  double get speed => _player.speed;

  Future<void> init() async {
    await _player.setLoopMode(LoopMode.off);
    await _configureAudioSession();
  }

  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              // 修复荣耀平板 V8 Pro 音量忽高忽低问题
              // 不再降低音量，而是保持原音量（避免频繁 duck/unduck 导致波动）
              // _player.setVolume(0.5);  // 注释掉：会导致音量波动
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              if (_player.playing) {
                // 标记为"被打断的暂停"，恢复焦点时自动续播；
                // 直接调用 _player.pause() 绕过公开 pause()，保留标记
                _pausedByInterruption = true;
                _player.pause();
              }
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              // 恢复时也不再调整音量，保持 1.0
              // _player.setVolume(1.0);  // 注释掉：避免音量波动
              break;
            case AudioInterruptionType.pause:
              // 仅当之前是被打断导致的暂停时，才自动恢复播放。
              // 用户手动暂停后其他 app 短暂占用焦点又释放时，标记为 false，
              // 不会进入此分支，避免错误自动续播。
              if (_pausedByInterruption &&
                  !_player.playing &&
                  _player.processingState == ProcessingState.ready) {
                _pausedByInterruption = false;
                play();
              }
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });
      session.becomingNoisyEventStream.listen((_) {
        if (_player.playing) {
          // 拔耳机暂停不算"被打断"，焦点恢复时不应自动续播
          _pausedByInterruption = false;
          _player.pause();
        }
      });
    } catch (e) {
          }
  }

  Future<void> play() async {
    // 用户主动播放：清除打断标记，避免后续焦点事件误判
    _pausedByInterruption = false;
    await _player.play();
  }

  Future<void> pause() async {
    // 用户主动暂停：清除打断标记，避免后续焦点恢复时错误自动播放
    _pausedByInterruption = false;
    await _player.pause();
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> setUrl(String url) async {
    await _player.setUrl(
      url,
      headers: const {},
    );
  }

  Future<void> setPlaylist(List<UriAudioSource> sources, {int startIndex = 0}) async {
    _playlistSource.clear();
    if (sources.isNotEmpty) {
      _playlistSource.addAll(sources);
    }
    await _player.setAudioSource(
      _playlistSource,
      initialIndex: startIndex,
      initialPosition: Duration.zero,
    );
  }

  Future<void> addAudioSource(UriAudioSource source) async {
    await _playlistSource.add(source);
  }

  Future<void> addAllAudioSources(List<UriAudioSource> sources) async {
    await _playlistSource.addAll(sources);
  }

  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  Future<void> seekToNext() async {
    await _player.seekToNext();
  }

  Future<void> seekToPrevious() async {
    await _player.seekToPrevious();
  }

  Future<void> setLoopMode(LoopMode mode) async {
    await _player.setLoopMode(mode);
  }

  Future<void> setShuffleModeEnabled(bool enabled) async {
    await _player.setShuffleModeEnabled(enabled);
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}

UriAudioSource createAudioSource({
  required String id,
  required String url,
  required String title,
  String? artist,
  String? album,
  Uri? artUri,
}) {
  return AudioSource.uri(
    Uri.parse(url),
    tag: {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'artUri': artUri?.toString(),
    },
  );
}
