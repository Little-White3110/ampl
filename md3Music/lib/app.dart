import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/layout/responsive_layout.dart';
import 'core/theme/app_theme.dart';
import 'data/models/playlist.dart';
import 'main.dart' show appNavigatorKey;
import 'modules/charts/charts_page.dart';
import 'modules/discover/discover_page.dart';
import 'modules/user/user_center_page.dart';
import 'modules/user/favorites_page.dart';

import 'modules/player/full_player.dart';
import 'modules/player/mini_player.dart';
import 'modules/playlist/playlist_page.dart';
import 'modules/search/search_page.dart';
import 'modules/settings/settings_page.dart';
import 'modules/library/library_page.dart';
import 'modules/login/login_page.dart';
import 'modules/personal_fm/personal_fm_page.dart';
import 'providers/downloads_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/kugou_provider.dart';
import 'providers/library_provider.dart';
import 'providers/player_provider.dart';
import 'providers/playlist_collection_notifier.dart';
import 'providers/theme_provider.dart';
import 'services/nodejs_server.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
        ChangeNotifierProvider(create: (_) => KugouProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider(create: (_) => DownloadsProvider()),
        // 跨页面广播「收藏的歌单」变更（详情页 → 我的收藏 tab 立即刷新）
        ChangeNotifierProvider(create: (_) => PlaylistCollectionNotifier()),
      ],
      child: const _AppView(),
    );
  }
}

class _AppView extends StatelessWidget {
  const _AppView();

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      title: 'MD3Music',
      debugShowCheckedModeBanner: false,
      // 同时传 theme 和 darkTheme，并根据 ThemeProvider.effectiveSeedColor
      // 动态生成（支持「莫奈色」开关切换系统主色）。
      theme: AppTheme.lightThemeFromSeed(themeProvider.effectiveSeedColor),
      darkTheme: AppTheme.darkThemeFromSeed(themeProvider.effectiveSeedColor),
      themeMode: themeProvider.themeMode,
      navigatorKey: appNavigatorKey,
      initialRoute: '/',
      routes: {
        '/': (_) => const _MainLayout(),
        '/search': (_) => const SearchPage(),
        '/library': (_) => const LibraryPage(),
        '/settings': (_) => const SettingsPage(),
        // 发现页右上角头像点击跳转入口（push 独立路由，与底部 tab 中的实例并存无冲突）
        '/user': (_) => const UserCenterPage(),
        '/player': (_) => const FullPlayer(),
        '/personal_fm': (_) => const PersonalFmPage(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/playlist') {
          final playlist = settings.arguments as Playlist;
          return PageRouteBuilder(
            pageBuilder: (_, _, _) => PlaylistPage(playlist: playlist),
            transitionsBuilder: (_, animation, _, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          );
        }
        return null;
      },
    );
  }
}

class _MainLayout extends StatefulWidget {
  const _MainLayout();

  @override
  State<_MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<_MainLayout> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    DiscoverPage(),
    ChartsPage(),
    FavoritesPage(),
    PersonalFmPage(),
    UserCenterPage(),
  ];

  @override
  void initState() {
    super.initState();
    // 未登录时尝试播放联网歌曲,弹出登录提示
    context.read<PlayerProvider>().onLoginRequired = _showLoginRequiredDialog;
    // 监听应用生命周期：detached（进程被系统销毁前的最后窗口）时尝试关停本地 Node.js
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 当系统即将销毁应用进程时（包含后台划掉 / 系统回收），Flutter 会先收到 detached。
    // 此时同步触发 Node.js 关闭：若进程随之被 kill 也无副作用；若进程仍存活则关闭 libuv。
    if (state == AppLifecycleState.detached) {
      // 同步触发即可，Dart 端很快；不 await，避免阻塞 framework 销毁流程
      // ignore: discarded_futures
      NodeJsServer.stop();
    }
  }

  void _showLoginRequiredDialog() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('请先登录'),
        content: const Text('播放音乐需要登录账号,是否前往登录?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const LoginPage()));
            },
            child: const Text('去登录'),
          ),
        ],
      ),
    );
  }

  /// 预见性返回开关关闭时，栈空按返回键弹出的退出确认框。
  /// 用户选择「退出」时调用 SystemNavigator.pop() 退出 App。
  Future<void> _showExitDialog() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出应用'),
        content: const Text('确定要退出 MD3Music 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (shouldExit == true && mounted) {
      SystemNavigator.pop();
    }
  }

  static const List<NavigationDestination> _destinations = [
    NavigationDestination(
      icon: Icon(Icons.explore_outlined),
      selectedIcon: Icon(Icons.explore),
      label: '发现',
    ),
    NavigationDestination(
      icon: Icon(Icons.trending_up_outlined),
      selectedIcon: Icon(Icons.trending_up),
      label: '排行',
    ),
    NavigationDestination(
      icon: Icon(Icons.favorite_outline),
      selectedIcon: Icon(Icons.favorite),
      label: '我收藏',
    ),
    NavigationDestination(
      icon: Icon(Icons.radio_outlined),
      selectedIcon: Icon(Icons.radio),
      label: '私人FM',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outlined),
      selectedIcon: Icon(Icons.person),
      label: '我的',
    ),
  ];

  static const List<NavigationRailDestination> _railDestinations = [
    NavigationRailDestination(
      icon: Icon(Icons.explore_outlined),
      selectedIcon: Icon(Icons.explore),
      label: Text('发现'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.trending_up_outlined),
      selectedIcon: Icon(Icons.trending_up),
      label: Text('排行'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.favorite_outline),
      selectedIcon: Icon(Icons.favorite),
      label: Text('我收藏'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.radio_outlined),
      selectedIcon: Icon(Icons.radio),
      label: Text('私人FM'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.person_outlined),
      selectedIcon: Icon(Icons.person),
      label: Text('我的'),
    ),
  ];

  static const List<NavigationDrawerDestination> _drawerDestinations = [
    NavigationDrawerDestination(
      icon: Icon(Icons.explore_outlined),
      selectedIcon: Icon(Icons.explore),
      label: Text('发现'),
    ),
    NavigationDrawerDestination(
      icon: Icon(Icons.trending_up_outlined),
      selectedIcon: Icon(Icons.trending_up),
      label: Text('排行'),
    ),
    NavigationDrawerDestination(
      icon: Icon(Icons.favorite_outline),
      selectedIcon: Icon(Icons.favorite),
      label: Text('我收藏'),
    ),
    NavigationDrawerDestination(
      icon: Icon(Icons.radio_outlined),
      selectedIcon: Icon(Icons.radio),
      label: Text('私人FM'),
    ),
    NavigationDrawerDestination(
      icon: Icon(Icons.person_outlined),
      selectedIcon: Icon(Icons.person),
      label: Text('我的'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // 读取预见性返回开关：
    // - 开启（默认）：canPop: true 启用预测返回手势，栈空直接退出 App
    // - 关闭：canPop: false 禁用预测动画，栈空时 onPopInvokedWithResult
    //   被调用且 didPop 为 false，弹出退出确认框
    final predictiveBackEnabled = context.watch<ThemeProvider>().predictiveBackEnabled;
    return PopScope(
      canPop: predictiveBackEnabled,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _showExitDialog();
        }
      },
      child: ResponsiveScaffold(
        destinations: _destinations,
        railDestinations: _railDestinations,
        drawerDestinations: _drawerDestinations,
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        body: Column(
          children: [
            Expanded(child: _pages[_selectedIndex]),
            const MiniPlayer(),
          ],
        ),
        compactBody: Column(
          children: [
            Expanded(child: _pages[_selectedIndex]),
            const MiniPlayer(),
          ],
        ),
        mediumBody: Column(
          children: [
            Expanded(child: _pages[_selectedIndex]),
            const MiniPlayer(),
          ],
        ),
        expandedBody: Column(
          children: [
            Expanded(child: _pages[_selectedIndex]),
            const MiniPlayer(),
          ],
        ),
      ),
    );
  }
}
