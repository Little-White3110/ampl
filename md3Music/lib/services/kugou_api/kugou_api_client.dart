import 'dart:async';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kugou_endpoints.dart';
import 'kugou_models.dart';

class KugouApiClient {
  static final KugouApiClient _instance = KugouApiClient._internal();

  factory KugouApiClient() => _instance;

  KugouApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: KugouEndpoints.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Accept': 'application/json'},
        extra: {'withCredentials': true},
      ),
    );

    _dio.interceptors.add(InterceptorsWrapper(onRequest: _onRequest));

    _initFromStorage();
  }

  late final Dio _dio;

  /// 暴露 Dio 实例供外部使用（如 DownloadsProvider 下载封面图）。
  Dio get dio => _dio;

  String? _token;
  String? _userid;
  String? _vipToken;
  String? _dfid;
  bool _isInitialized = false;
  Completer<void>? _initCompleter;

  static const _loginPaths = {
    '/login/qr/key', '/login/qr/create', '/login/qr/check',
    '/login/cellphone', '/login/token', '/login',
    '/login/wx/create', '/login/wx/check',
    '/login/openplat', '/login/device', '/login/device/kick',
    '/captcha/sent',
    '/youth/day/vip', '/youth/day/vip/upgrade', '/youth/month/vip/record',
  };

  void _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_isInitialized) {
      await _initCompleter?.future;
    }

    // 登录相关接口直接走云服务器，避免 local→cloud 双重签名
    if (_loginPaths.contains(options.path)) {
      options.baseUrl = 'http://115.29.236.96:5621';
    } else {
      options.baseUrl = KugouEndpoints.baseUrl;
    }

    // 关键修复：每次请求前验证用户身份
    if (_token != null && _userid != null) {
      // 把 vip_token 一并写入 Authorization，服务端的 cookieToJson
      // 会按 ; 切成 cookie 对象，song_url_new 等模块可直接读取。
      final authParts = <String>['token=$_token', 'userid=$_userid'];
      if (_vipToken != null && _vipToken!.isNotEmpty) {
        authParts.add('vip_token=$_vipToken');
      }
      options.headers['Authorization'] = authParts.join(';');

      // 调试日志：打印请求的用户身份（生产环境可移除）
      print('🌐 [API Request] User: $_userid, URL: ${options.path}');
          } else {
      // 未登录，清除 Authorization 头
      options.headers.remove('Authorization');
      print('⚠️ [API Request] 未登录状态, URL: ${options.path}');
          }

    if (_dfid != null) {
      options.queryParameters['dfid'] = _dfid;
    }

    // 调用方通过 options.extra['noCache'] = true 标记需要绕过 server_android 的 apicache。
    // server_android 的 apicache 中间件认 x-apicache-bypass / x-apicache-force-fetch 头
    // （util/apicache.js L596-597）。这样"我的收藏"新增/取消后下拉刷新能立刻拿到新数据，
    // 不必等 2 分钟过期。
    final extra = options.extra;
    if (extra['noCache'] == true) {
      options.headers['x-apicache-bypass'] = '1';
      options.headers['Cache-Control'] = 'no-cache';
      // 同时给查询参数加 t= 戳，避免部分路径在 cache 命中时跳过参数比对
      if (options.queryParameters['t'] == null) {
        options.queryParameters['t'] = DateTime.now().millisecondsSinceEpoch;
      }
    } else {
      options.headers.remove('x-apicache-bypass');
      options.headers.remove('Cache-Control');
    }

    handler.next(options);
  }

  void setBaseUrl(String url) {
    final cleanUrl = url.replaceAll(RegExp(r'/+$'), '');
    KugouEndpoints.baseUrl = cleanUrl;
    _dio.options.baseUrl = cleanUrl;
    _dfid = null;
    registerDevice();
  }

  Future<Map<String, dynamic>?> _get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool noCache = false,
  }) async {
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
        options: Options(extra: {'noCache': noCache}),
      );
      if (response.statusCode == 200) {
        if (response.data is Map<String, dynamic>) {
          return response.data as Map<String, dynamic>;
        }
      }
      print('[API _get] Non-200 or non-map: status=${response.statusCode} data=${response.data}');
      return null;
    } on DioException catch (e) {
      print('[API _get] DioException: ${e.type} ${e.message} response=${e.response?.statusCode} ${e.response?.data}');
      return null;
    } catch (e) {
      print('[API _get] Error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _post(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    bool noCache = false,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(extra: {'noCache': noCache}),
      );
      if (response.statusCode == 200) {
        if (response.data is Map<String, dynamic>) {
          return response.data as Map<String, dynamic>;
        }
      }
      print('[API _post] Non-200 or non-map: status=${response.statusCode} data=${response.data}');
      return null;
    } on DioException catch (e) {
      print('[API _post] DioException: ${e.type} ${e.message} response=${e.response?.statusCode} ${e.response?.data}');
      return null;
    } catch (e) {
      print('[API _post] Error: $e');
      return null;
    }
  }

  Future<void> _initFromStorage() async {
    _initCompleter = Completer<void>();
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 先读取当前登录的用户ID
      final currentUserid = prefs.getString('kugou_current_userid');
      
      if (currentUserid != null && currentUserid.isNotEmpty) {
        // 从用户隔离的键名读取
        final userTokenKey = 'kugou_token_$currentUserid';
        final userIdKey = 'kugou_userid_$currentUserid';
        final userVipKey = 'kugou_vip_token_$currentUserid';
        
        _token = prefs.getString(userTokenKey);
        _userid = prefs.getString(userIdKey);
        _vipToken = prefs.getString(userVipKey);
        
        if (_token != null && _userid != null) {
          print('✅ [Auth] 从存储加载登录状态，用户ID: $_userid');
        } else {
          // 用户隔离键没有，尝试旧版本全局键
          _token = prefs.getString('kugou_token');
          _userid = prefs.getString('kugou_userid');
          _vipToken = prefs.getString('kugou_vip_token');
          
          if (_token != null && _userid != null) {
            print('⚠️ [Auth] 检测到旧版本登录状态，建议重新登录');
          }
        }
      } else {
        // 没有 currentUserid，尝试旧版本全局键
        _token = prefs.getString('kugou_token');
        _userid = prefs.getString('kugou_userid');
        _vipToken = prefs.getString('kugou_vip_token');
        
        if (_token != null && _userid != null) {
          print('⚠️ [Auth] 检测到旧版本登录状态，建议重新登录');
        }
      }
      
      _dfid = prefs.getString('kugou_dfid');
          } catch (e) {
      print('❌ [Auth] 从存储初始化失败: $e');
          } finally {
      _isInitialized = true;
      _initCompleter?.complete();
    }
  }

  Future<void> setLoginCookies(
    String token,
    String userid, {
    String? vipToken,
  }) async {
    // 关键修复：先清除旧的用户数据，再设置新的
    await clearCookies();
    
    _token = token;
    _userid = userid;
    _vipToken = vipToken;
    
    // 使用用户隔离的键名，避免多用户数据混乱
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 清除所有可能的旧键（兼容旧版本）
      await prefs.remove('kugou_token');
      await prefs.remove('kugou_userid');
      await prefs.remove('kugou_vip_token');
      await prefs.remove('kugou_dfid');
      
      // 使用带用户ID的键名存储（防止多用户冲突）
      final userTokenKey = 'kugou_token_$userid';
      final userIdKey = 'kugou_userid_$userid';
      final userVipKey = 'kugou_vip_token_$userid';
      final currentUserKey = 'kugou_current_userid';
      
      await prefs.setString(userTokenKey, token);
      await prefs.setString(userIdKey, userid);
      if (vipToken != null && vipToken.isNotEmpty) {
        await prefs.setString(userVipKey, vipToken);
      }
      
      // 记录当前登录的用户ID
      await prefs.setString(currentUserKey, userid);
      
      print('✅ [Auth] 登录成功，用户ID: $userid, Token已存储到: $userTokenKey');
          } catch (e) {
      print('❌ [Auth] 保存登录状态失败: $e');
          }
  }

  Future<void> clearCookies() async {
    final oldUserid = _userid;
    
    _token = null;
    _userid = null;
    _vipToken = null;
    _dfid = null;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 清除用户隔离的键
      if (oldUserid != null && oldUserid.isNotEmpty) {
        await prefs.remove('kugou_token_$oldUserid');
        await prefs.remove('kugou_userid_$oldUserid');
        await prefs.remove('kugou_vip_token_$oldUserid');
      }
      
      // 清除所有可能的旧版本键
      await prefs.remove('kugou_token');
      await prefs.remove('kugou_userid');
      await prefs.remove('kugou_vip_token');
      await prefs.remove('kugou_current_userid');
      await prefs.remove('kugou_dfid');
      
      print('✅ [Auth] 已清除登录状态');
    } catch (e) {
      print('❌ [Auth] 清除登录状态失败: $e');
    }
  }

  // ==================== Device ====================

  Future<void> registerDevice() async {
    try {
      final json = await _get(KugouEndpoints.registerDev);
      if (json != null) {
        final data = json['data'] as Map<String, dynamic>?;
        if (data != null && data['dfid'] != null) {
          _dfid = data['dfid'].toString();
                  }
      }
    } catch (e) {
          }
  }

  bool _hasCandidates(Map<String, dynamic> json) {
    final candidates = json['candidates'];
    return candidates is List && candidates.isNotEmpty;
  }

  // ==================== Search ====================

  Future<KugouSearchResult?> search(
    String keywords, {
    int page = 1,
    int pagesize = 30,
    String type = 'song',
  }) async {
    final json = await _get(
      KugouEndpoints.search,
      queryParameters: {
        'keywords': keywords,
        'page': page,
        'pagesize': pagesize,
        'type': type,
      },
    );
    if (json == null) return null;
    try {
      return KugouSearchResult.fromJson(json);
    } catch (e) {
            return null;
    }
  }

  Future<List<KugouAlbumBrief>?> searchAlbums(String keywords, {int page = 1, int pagesize = 20}) async {
    final json = await _get(
      KugouEndpoints.searchAlbum,
      queryParameters: {'keyword': keywords, 'page': page, 'pagesize': pagesize},
    );
    if (json == null) return null;
    try {
      final data = json['data'];
      List<dynamic> list;
      if (data is List) {
        list = data;
      } else if (data is Map<String, dynamic>) {
        list = (data['list'] ?? data['info'] ?? []) as List<dynamic>;
      } else {
        list = [];
      }
      return list.map((e) => KugouAlbumBrief.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
            return null;
    }
  }

  Future<List<KugouPlaylistBrief>?> searchPlaylists(String keywords, {int page = 1, int pagesize = 20}) async {
    final json = await _get(
      KugouEndpoints.searchSpecial,
      queryParameters: {'keywords': keywords, 'page': page, 'pagesize': pagesize},
    );
    if (json == null) return null;
    try {
      final data = json['data'];
      List<dynamic> list;
      if (data is List) {
        list = data;
      } else if (data is Map<String, dynamic>) {
        list = (data['list'] ?? data['info'] ?? []) as List<dynamic>;
      } else {
        list = [];
      }
      return list.map((e) => KugouPlaylistBrief.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
            return null;
    }
  }

  Future<Map<String, dynamic>?> searchComplex(String keywords) async {
    return await _get(
      KugouEndpoints.searchComplex,
      queryParameters: {'keywords': keywords},
    );
  }

  Future<String?> searchDefault() async {
    final json = await _get(KugouEndpoints.searchDefault);
    if (json == null) return null;
    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      return data['keyword']?.toString();
    } catch (e) {
            return null;
    }
  }

  Future<List<String>?> getHotSearch() async {
    final json = await _get(KugouEndpoints.searchHot);
    if (json == null) return null;
    try {
      final data = json['data'];
      List<dynamic> list;
      if (data is List) {
        list = data;
      } else if (data is Map<String, dynamic>) {
        list = (data['list'] ?? data['info'] ?? []) as List<dynamic>;
      } else {
        list = [];
      }
      return list.map((e) => e.toString()).toList();
    } catch (e) {
            return null;
    }
  }

  // ==================== Song ====================

  Future<KugouSongDetail?> getSongDetail(String hash) async {
    final json = await _get(
      KugouEndpoints.songDetail,
      queryParameters: {'hash': hash.toLowerCase()},
    );
    if (json == null) return null;
    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      return KugouSongDetail.fromJson(data);
    } catch (e) {
            return null;
    }
  }

  Future<KugouPlayUrl?> getSongUrl(
    String hash, {
    String quality = KugouQuality.standard,
    String? albumId,
    String? albumAudioId,
  }) async {
    final params = <String, dynamic>{
      'hash': hash.toLowerCase(),
      'quality': quality,
    };
    if (albumId != null) params['album_id'] = albumId;
    if (albumAudioId != null) params['album_audio_id'] = albumAudioId;

    final json = await _get(
      KugouEndpoints.songUrl,
      queryParameters: params,
    );
    if (json == null) return null;

    // 优先从 vip 接口取完整链接
    if (hasVipToken) {
      final vipUrl = await _getSongUrlNew(
        hash,
        quality: quality,
        albumId: albumId,
        albumAudioId: albumAudioId,
      );
      if (vipUrl != null) return vipUrl;
    }

    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      return KugouPlayUrl.fromJson(data);
    } catch (e) {
            return null;
    }
  }

  Future<KugouPlayUrl?> getSongUrlWithFallback(
    String hash, {
    String quality = KugouQuality.standard,
    String? albumId,
    String? albumAudioId,
  }) async {
    final params = <String, dynamic>{
      'hash': hash.toLowerCase(),
      'quality': quality,
    };
    if (albumId != null) params['album_id'] = albumId;
    if (albumAudioId != null) params['album_audio_id'] = albumAudioId;

    final json = await _get(
      KugouEndpoints.songUrl,
      queryParameters: params,
    );
    if (json == null) return null;

    if (hasVipToken) {
      try {
        if (hasVipToken) {
          final vipUrl = await _getSongUrlNew(
            hash,
            quality: quality,
            albumId: albumId,
            albumAudioId: albumAudioId,
          );
          if (vipUrl != null) return vipUrl;
        }
      } catch (e) {
              }
    }

    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      return KugouPlayUrl.fromJson(data);
    } catch (e) {
            return null;
    }
  }

  /// VIP 专属接口：获取完整播放链接（非试听片段）。
  /// 与 getSongUrl 的区别：url 字段是完整链接，play_backup_url 也是完整链接。
  /// 即便 url 字段非空也不能直接拿来用，否则会播放到片段末尾就跳结束。
  Future<KugouPlayUrl?> _getSongUrlNew(
    String hash, {
    String quality = KugouQuality.standard,
    String? albumId,
    String? albumAudioId,
  }) async {
    final query = <String, dynamic>{
      'hash': hash.toLowerCase(),
      'quality': quality,
    };
    if (albumId != null) query['album_id'] = albumId;
    if (albumAudioId != null) query['album_audio_id'] = albumAudioId;

    final json = await _get(
      KugouEndpoints.songUrlNew,
      queryParameters: query,
    );
    if (json == null) return null;

    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      final url = data['url']?.toString();
      final playUrl = data['play_url']?.toString();
      final backupUrl = data['play_backup_url']?.toString();

      // 优先取 url（完整链接），其次 play_url，最后 play_backup_url
      final finalUrl = url ?? playUrl ?? backupUrl;
      if (finalUrl == null || finalUrl.isEmpty) {
                return null;
      }

      return KugouPlayUrl(
        url: finalUrl,
        fileSize: _parseInt(data['fileSize'] ?? data['filesize'] ?? 0),
        bitRate: _parseInt(data['bitRate'] ?? data['bitrate'] ?? 0),
        quality: data['quality']?.toString() ?? quality,
      );
    } catch (e) {
            return null;
    }
  }

  int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  // ==================== Lyric ====================

  Future<KugouLyric?> getLyric(
    String hash, {
    String? accesskey,
    String? songName,
    String fmt = 'lrc',
    bool decode = true,
  }) async {
    String? lyricId;
    String? lyricAccesskey;

    Map<String, dynamic>? searchResult = await _get(
      KugouEndpoints.searchLyric,
      queryParameters: {'hash': hash.toLowerCase()},
    );

    if (searchResult != null &&
        !_hasCandidates(searchResult) &&
        songName != null &&
        songName.isNotEmpty) {
            searchResult = await _get(
        KugouEndpoints.searchLyric,
        queryParameters: {'keywords': songName, 'hash': hash.toLowerCase()},
      );
    }

    if (searchResult != null) {
      try {
        final candidates = searchResult['candidates'];
        if (candidates is List && candidates.isNotEmpty) {
          final first = candidates.first as Map<String, dynamic>;
          lyricId = first['id']?.toString();
          lyricAccesskey = first['accesskey']?.toString();
        }
      } catch (e) {
              }
    }

    if (lyricId == null) {
                  return null;
    }

    // 默认 fmt='lrc' 触发并发双请求（LRC + KRC）；显式传 fmt='krc' 走单请求路径（向后兼容）
    final bool dualRequest = (fmt == 'lrc');

    if (dualRequest) {
      // 并发双请求：Future.wait 同时发起，每个请求独立 try/catch 防止单点失败
      final results = await Future.wait([
        _fetchLyricContent(lyricId, lyricAccesskey, 'lrc', decode),
        _fetchLyricContent(lyricId, lyricAccesskey, 'krc', decode),
      ]);
      final lrcJson = results[0];
      final krcJson = results[1];
      return mergeLyricResponses(lrcJson, krcJson);
    }

    // 单请求路径（显式 fmt=krc 等非 lrc 场景）
    final json = await _fetchLyricContent(lyricId, lyricAccesskey, fmt, decode);
    if (json == null) return null;
    try {
      return KugouLyric.fromJson(json);
    } catch (e) {
            return null;
    }
  }

  /// 抽取的私有方法：发起单个歌词下载请求，返回响应中的 data 节点。
  /// 任何异常都吞掉返回 null，确保并发场景下单个请求失败不影响另一个。
  Future<Map<String, dynamic>?> _fetchLyricContent(
    String lyricId,
    String? lyricAccesskey,
    String fmt,
    bool decode,
  ) async {
    try {
      final params = <String, dynamic>{
        'id': lyricId,
        'fmt': fmt,
        'decode': decode.toString(),
      };
      if (lyricAccesskey != null) params['accesskey'] = lyricAccesskey;
      final json = await _get(KugouEndpoints.lyric, queryParameters: params);
      if (json == null) return null;
      return json['data'] as Map<String, dynamic>? ?? json;
    } catch (e) {
      // 单点失败不影响另一个并发请求
      return null;
    }
  }

  /// 合并 LRC 与 KRC 两个响应，构造同时携带两种明文的 KugouLyric。
  /// 抽为静态方法便于单元测试（无需 mock HTTP）。
  ///
  /// 字段映射规则（依 spec.md "Requirement: KRC 双请求与降级"）：
  /// - LRC 响应的 `decodeContent` → `KugouLyric.decodedContent`
  /// - KRC 响应的 `decodeContent` → `KugouLyric.decodedKrcContent`
  ///
  /// 注意：`KugouLyric.fromJson` 会把 `decodeContent` 统一映射到 `decodedContent`，
  /// 因此对 KRC 响应不能直接用 fromJson 的 `decodedKrcContent` 字段（除非上游
  /// 显式返回 `decodeKrcContent` / `decoded_krc_content` / `krcContent`）。
  /// 这里对 KRC 响应做特殊处理：优先取专用字段，否则把 `decodeContent` 作为 KRC 明文。
  /// 两者都为 null 时返回 null。
  static KugouLyric? mergeLyricResponses(
    Map<String, dynamic>? lrcJson,
    Map<String, dynamic>? krcJson,
  ) {
    if (lrcJson == null && krcJson == null) return null;

    final lrcLyric =
        lrcJson != null ? KugouLyric.fromJson(lrcJson) : null;
    final krcLyric =
        krcJson != null ? KugouLyric.fromJson(krcJson) : null;

    // KRC 明文：优先用专用字段，否则把 KRC 响应的 decodeContent 当作 KRC 明文
    String? krcContent;
    if (krcJson != null) {
      final explicitKrc = krcJson['decodeKrcContent'] ??
          krcJson['decoded_krc_content'] ??
          krcJson['krcContent'];
      if (explicitKrc != null) {
        krcContent = explicitKrc.toString();
      } else if (krcJson['decodeContent'] != null) {
        krcContent = krcJson['decodeContent'].toString();
      }
    }

    return KugouLyric(
      content: lrcLyric?.content ?? krcLyric?.content ?? '',
      decodedContent: lrcLyric?.decodedContent,
      decodedKrcContent: krcContent,
      translatedContent:
          lrcLyric?.translatedContent ?? krcLyric?.translatedContent,
    );
  }

  // ==================== Comment ====================

  Future<KugouCommentList?> getComments(
    String hash, {
    String? albumAudioId,
    int page = 1,
    int pagesize = 20,
  }) async {
    final params = <String, dynamic>{
      'hash': hash,
      'page': page,
      'pagesize': pagesize,
    };
    if (albumAudioId != null) params['album_audio_id'] = albumAudioId;
    final json = await _get(
      KugouEndpoints.commentMusic,
      queryParameters: params,
    );
    if (json == null) return null;
    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      return KugouCommentList.fromJson(data);
    } catch (e) {
            return null;
    }
  }

  // ==================== Album ====================

  Future<KugouAlbumDetail?> getAlbumDetail(String albumId) async {
    final json = await _get(
      KugouEndpoints.albumDetail,
      queryParameters: {'albumid': albumId},
    );
    if (json == null) return null;
    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      return KugouAlbumDetail.fromJson(data);
    } catch (e) {
            return null;
    }
  }

  Future<List<KugouAlbumBrief>?> getNewAlbums({int page = 1, int pagesize = 20}) async {
    final json = await _get(
      KugouEndpoints.albumList,
      queryParameters: {'page': page, 'pagesize': pagesize},
    );
    if (json == null) return null;
    try {
      final data = json['data'];
      List<dynamic> list;
      if (data is List) {
        list = data;
      } else if (data is Map<String, dynamic>) {
        list = (data['list'] ?? data['info'] ?? []) as List<dynamic>;
      } else {
        list = [];
      }
      return list.map((e) => KugouAlbumBrief.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
            return null;
    }
  }

  // ==================== Artist ====================

  Future<KugouArtistDetail?> getArtistDetail(String artistId) async {
    final json = await _get(
      KugouEndpoints.artistDetail,
      queryParameters: {'artistid': artistId},
    );
    if (json == null) return null;
    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      return KugouArtistDetail.fromJson(data);
    } catch (e) {
            return null;
    }
  }

  Future<List<Song>?> getArtistSongs(String artistId, {int page = 1, int pagesize = 30}) async {
    final json = await _get(
      KugouEndpoints.artistSongs,
      queryParameters: {'artistid': artistId, 'page': page, 'pagesize': pagesize},
    );
    if (json == null) return null;
    try {
      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return null;
      final list = (data['list'] ?? data['songs'] ?? []) as List<dynamic>;
      return list
          .map((e) {
            try {
              return KugouSongDetail.fromJson(e as Map<String, dynamic>).toSong();
            } catch (_) {
              return null;
            }
          })
          .where((s) => s != null)
          .cast<Song>()
          .toList();
    } catch (e) {
            return null;
    }
  }

  // ==================== Playlist / Sheet ====================

  Future<KugouPlaylistDetail?> getPlaylistDetail(String specialId) async {
    final json = await _get(
      KugouEndpoints.playlistDetail,
      queryParameters: {'specialid': specialId},
    );
    if (json == null) return null;
    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      return KugouPlaylistDetail.fromJson(data);
    } catch (e) {
            return null;
    }
  }

  Future<List<KugouPlaylistBrief>?> getRecommendPlaylists({int page = 1, int pagesize = 20}) async {
    final json = await _get(
      KugouEndpoints.playlistRecommend,
      queryParameters: {'page': page, 'pagesize': pagesize},
    );
    if (json == null) return null;
    try {
      final data = json['data'];
      List<dynamic> list;
      if (data is List) {
        list = data;
      } else if (data is Map<String, dynamic>) {
        list = (data['list'] ?? data['info'] ?? []) as List<dynamic>;
      } else {
        list = [];
      }
      return list.map((e) => KugouPlaylistBrief.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
            return null;
    }
  }

  Future<Map<String, dynamic>?> getSheetDetail(String id) async {
    return await _get(KugouEndpoints.sheetDetail, queryParameters: {'id': id});
  }

  // ==================== Rank ====================

  Future<List<KugouPlaylistBrief>?> getRankList() async {
    final json = await _get(KugouEndpoints.rankList);
    if (json == null) return null;
    try {
      final data = json['data'];
      List<dynamic> list;
      if (data is List) {
        list = data;
      } else if (data is Map<String, dynamic>) {
        list = (data['list'] ?? data['info'] ?? []) as List<dynamic>;
      } else {
        list = [];
      }
      return list.map((e) {
        try {
          return KugouPlaylistBrief.fromJson(e as Map<String, dynamic>);
        } catch (_) {
          return null;
        }
      }).where((p) => p != null).cast<KugouPlaylistBrief>().toList();
    } catch (e) {
            return null;
    }
  }

  Future<KugouPlaylistDetail?> getRankDetail(String rankId, {int page = 1, int pagesize = 30}) async {
    final json = await _get(
      KugouEndpoints.rankInfo,
      queryParameters: {'rankid': rankId, 'page': page, 'pagesize': pagesize},
    );
    if (json == null) return null;
    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      return KugouPlaylistDetail.fromJson(data);
    } catch (e) {
            return null;
    }
  }

  // ==================== Collection ====================

  /// 收藏歌单（订阅）
  /// 返回 true 表示收藏成功
  Future<bool> collectPlaylist(String specialId) async {
    try {
      final result = await _post(
        '/mv/action/collect',
        data: {'specialid': specialId},
      );
      return result != null && (result['status'] == 1 || result['errcode'] == 0);
    } catch (e) {
            return false;
    }
  }

  /// 取消收藏歌单（取消订阅）
  /// 返回 true 表示取消成功
  Future<bool> uncollectPlaylist(String specialId) async {
    try {
      final result = await _post(
        '/mv/action/uncollect',
        data: {'specialid': specialId},
      );
      return result != null && (result['status'] == 1 || result['errcode'] == 0);
    } catch (e) {
            return false;
    }
  }

  // ==================== Login ====================

  /// 获取登录二维码
  Future<KugouQrLogin?> getQrKey() async {
    final json = await _get(KugouEndpoints.qrKey);
    if (json == null) return null;
    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      return KugouQrLogin.fromJson(data);
    } catch (e) {
            return null;
    }
  }

  /// 创建登录二维码（返回二维码内容）
  Future<String?> createQrCode(String key) async {
    final json = await _get(
      KugouEndpoints.qrCreate,
      queryParameters: {'key': key},
    );
    if (json == null) return null;
    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      return data['content']?.toString() ?? data['url']?.toString();
    } catch (e) {
            return null;
    }
  }

  /// 检查二维码扫描状态
  /// 返回 0=未扫描, 1=已扫描待确认, 2=已确认, 3=已过期
  Future<int> checkQrStatus(String key) async {
    final json = await _get(
      KugouEndpoints.qrCheck,
      queryParameters: {'key': key},
    );
    if (json == null) return 3;
    try {
      final status = json['status'] ?? json['data']?['status'];
      if (status is int) return status;
      return int.tryParse(status.toString()) ?? 3;
    } catch (e) {
            return 3;
    }
  }

  /// 获取用户信息（登录成功后调用）
  Future<KugouUserInfo?> getUserInfo() async {
    final json = await _get(KugouEndpoints.userInfo);
    if (json == null) return null;
    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      return KugouUserInfo.fromJson(data);
    } catch (e) {
            return null;
    }
  }

  /// 手机号登录
  Future<Map<String, dynamic>?> loginByPhone(String phone, String code) async {
    final result = await _post(
      KugouEndpoints.loginPhone,
      data: {'phone': phone, 'code': code},
    );
    return result;
  }

  /// 发送验证码
  Future<bool> sendSmsCode(String phone) async {
    try {
      final result = await _post(
        KugouEndpoints.smsCode,
        data: {'phone': phone},
      );
      return result != null && (result['status'] == 1 || result['errcode'] == 0);
    } catch (e) {
            return false;
    }
  }

  // ==================== User Collection ====================

  /// 获取用户收藏的歌单列表
  Future<List<KugouPlaylistBrief>?> getUserCollections({int page = 1, int pagesize = 30}) async {
    final json = await _get(
      KugouEndpoints.userCollections,
      queryParameters: {'page': page, 'pagesize': pagesize},
    );
    if (json == null) return null;
    try {
      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return null;
      final list = (data['list'] ?? data['info'] ?? []) as List<dynamic>;
      return list.map((e) => KugouPlaylistBrief.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
            return null;
    }
  }

  /// 获取用户收藏的歌曲列表（我喜欢）
  Future<List<Song>?> getUserFavoriteSongs({int page = 1, int pagesize = 30}) async {
    final json = await _get(
      KugouEndpoints.userFavoriteSongs,
      queryParameters: {'page': page, 'pagesize': pagesize},
    );
    if (json == null) return null;
    try {
      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return null;
      final list = (data['list'] ?? data['songs'] ?? []) as List<dynamic>;
      return list.map((e) {
        try {
          return KugouSongDetail.fromJson(e as Map<String, dynamic>).toSong();
        } catch (_) {
          return null;
        }
      }).where((s) => s != null).cast<Song>().toList();
    } catch (e) {
            return null;
    }
  }

  // ==================== VIP ====================

  /// 获取 VIP 信息
  Future<Map<String, dynamic>?> getVipInfo() async {
    final json = await _get(KugouEndpoints.vipInfo);
    if (json == null) return null;
    try {
      return json['data'] as Map<String, dynamic>? ?? json;
    } catch (e) {
            return null;
    }
  }

  // ==================== Daily Recommend ====================

  /// 获取每日推荐歌曲
  Future<List<Song>?> getDailyRecommendSongs() async {
    final json = await _get(KugouEndpoints.dailyRecommend);
    if (json == null) return null;
    try {
      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return null;
      final list = (data['list'] ?? data['songs'] ?? []) as List<dynamic>;
      return list.map((e) {
        try {
          return KugouSongDetail.fromJson(e as Map<String, dynamic>).toSong();
        } catch (_) {
          return null;
        }
      }).where((s) => s != null).cast<Song>().toList();
    } catch (e) {
            return null;
    }
  }

  // ==================== Recent Listen ====================

  /// 获取最近播放记录
  Future<List<Song>?> getRecentSongs({int page = 1, int pagesize = 30}) async {
    final json = await _get(
      KugouEndpoints.recentSongs,
      queryParameters: {'page': page, 'pagesize': pagesize},
    );
    if (json == null) return null;
    try {
      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return null;
      final list = (data['list'] ?? data['songs'] ?? []) as List<dynamic>;
      return list.map((e) {
        try {
          return KugouSongDetail.fromJson(e as Map<String, dynamic>).toSong();
        } catch (_) {
          return null;
        }
      }).where((s) => s != null).cast<Song>().toList();
    } catch (e) {
            return null;
    }
  }

  // ==================== Search Complex ====================

  /// 复合搜索（歌曲+歌单+专辑+歌手）
  Future<Map<String, dynamic>?> searchAll(String keywords) async {
    return await _get(
      KugouEndpoints.searchComplex,
      queryParameters: {'keywords': keywords},
    );
  }

  // ==================== Top/Hot ====================

  /// 获取热歌榜
  Future<List<Song>?> getHotSongs({int page = 1, int pagesize = 30}) async {
    final json = await _get(
      KugouEndpoints.top,
      queryParameters: {'page': page, 'pagesize': pagesize},
    );
    if (json == null) return null;
    try {
      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return null;
      final list = (data['list'] ?? data['songs'] ?? []) as List<dynamic>;
      return list.map((e) {
        try {
          return KugouSongDetail.fromJson(e as Map<String, dynamic>).toSong();
        } catch (_) {
          return null;
        }
      }).where((s) => s != null).cast<Song>().toList();
    } catch (e) {
            return null;
    }
  }

  // ==================== User Info Extended ====================

  /// 获取用户详细信息（头像、昵称等）
  Future<Map<String, dynamic>?> getUserDetail() async {
    final json = await _get('/user/detail');
    if (json == null) return null;
    try {
      return json['data'] as Map<String, dynamic>? ?? json;
    } catch (e) {
            return null;
    }
  }

  // ==================== Song Detail Extended ====================

  /// 获取歌曲详情（歌词、评论数等）
  Future<Map<String, dynamic>?> getSongInfo(String hash) async {
    final json = await _get(
      '/song/info',
      queryParameters: {'hash': hash.toLowerCase()},
    );
    if (json == null) return null;
    try {
      return json['data'] as Map<String, dynamic>? ?? json;
    } catch (e) {
            return null;
    }
  }

  // ==================== Favorites ====================

  /// 添加歌曲到收藏（我喜欢）
  Future<bool> addFavorite(String hash, {String? albumAudioId}) async {
    try {
      final data = <String, dynamic>{
        'hash': hash.toLowerCase(),
        'action': 'add',
      };
      if (albumAudioId != null) data['album_audio_id'] = albumAudioId;
      final result = await _post('/mv/action/add', data: data);
      return result != null && (result['status'] == 1 || result['errcode'] == 0);
    } catch (e) {
            return false;
    }
  }

  /// 取消收藏歌曲
  Future<bool> removeFavorite(String hash, {String? albumAudioId}) async {
    try {
      final data = <String, dynamic>{
        'hash': hash.toLowerCase(),
        'action': 'del',
      };
      if (albumAudioId != null) data['album_audio_id'] = albumAudioId;
      final result = await _post('/mv/action/add', data: data);
      return result != null && (result['status'] == 1 || result['errcode'] == 0);
    } catch (e) {
            return false;
    }
  }

  // ==================== Tag ====================

  /// 获取标签列表
  Future<List<Map<String, dynamic>>?> getTagList() async {
    final json = await _get(KugouEndpoints.tagList);
    if (json == null) return null;
    try {
      final data = json['data'];
      List<dynamic> list;
      if (data is List) {
        list = data;
      } else if (data is Map<String, dynamic>) {
        list = (data['list'] ?? data['info'] ?? []) as List<dynamic>;
      } else {
        list = [];
      }
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
            return null;
    }
  }

  /// 获取标签下歌单
  Future<List<KugouPlaylistBrief>?> getTagPlaylists(String tagId, {int page = 1, int pagesize = 20}) async {
    final json = await _get(
      KugouEndpoints.tagPlaylists,
      queryParameters: {'tagid': tagId, 'page': page, 'pagesize': pagesize},
    );
    if (json == null) return null;
    try {
      final data = json['data'];
      List<dynamic> list;
      if (data is List) {
        list = data;
      } else if (data is Map<String, dynamic>) {
        list = (data['list'] ?? data['info'] ?? []) as List<dynamic>;
      } else {
        list = [];
      }
      return list.map((e) => KugouPlaylistBrief.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
            return null;
    }
  }

  // ==================== Search History ====================

  /// 保存搜索历史
  Future<void> saveSearchHistory(String keyword) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('search_history') ?? [];
      list.remove(keyword); // 去重
      list.insert(0, keyword); // 最新在前
      if (list.length > 50) list.removeRange(50, list.length); // 最多保留50条
      await prefs.setStringList('search_history', list);
    } catch (e) {
          }
  }

  /// 获取搜索历史
  Future<List<String>> getSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList('search_history') ?? [];
    } catch (e) {
            return [];
    }
  }

  /// 清除搜索历史
  Future<void> clearSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('search_history');
    } catch (e) {
          }
  }

  // ==================== Play URL Extended ====================

  /// 获取播放链接（带试听标记）
  Future<KugouPlayUrl?> getSongPlayUrl(
    String hash, {
    String quality = '128',
    String? albumId,
    String? albumAudioId,
  }) async {
    return await getSongUrl(
      hash,
      quality: quality,
      albumId: albumId,
      albumAudioId: albumAudioId,
    );
  }

  // ==================== Token Status ====================

  String? get token => _token;
  String? get userid => _userid;
  String? get vipToken => _vipToken;
  String? get dfid => _dfid;
  bool get isLoggedIn => _token != null && _userid != null;
  bool get hasVipToken => _vipToken != null && _vipToken!.isNotEmpty;
}
