import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_theme.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _key = 'theme_mode';
  static const String _dynamicKey = 'use_dynamic_color';
  static const String _predictiveBackKey = 'predictive_back_enabled';

  ThemeMode _themeMode = ThemeMode.system;
  bool _useDynamicColor = false;
  Color? _systemSeedColor;
  // 预见性返回手势开关，默认开启；关闭后改为弹出退出确认框
  bool _predictiveBackEnabled = true;

  ThemeMode get themeMode => _themeMode;
  bool get useDynamicColor => _useDynamicColor;
  Color? get systemSeedColor => _systemSeedColor;
  bool get predictiveBackEnabled => _predictiveBackEnabled;

  /// 当前生效的种子色：
  /// - 启用系统主题色且成功取到 → 系统主色
  /// - 否则 → 默认紫色种子
  Color get effectiveSeedColor =>
      _useDynamicColor && _systemSeedColor != null
          ? _systemSeedColor!
          : AppTheme.defaultSeedColor;

  ThemeProvider() {
    _loadThemeMode();
    _loadDynamicColor();
    _loadPredictiveBack();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt(_key);
    if (savedIndex != null && savedIndex >= 0 && savedIndex < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[savedIndex];
      notifyListeners();
    }
  }

  Future<void> _saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, mode.index);
  }

  /// 加载「使用系统主题色」开关持久化值，若开启则同步提取系统主色。
  Future<void> _loadDynamicColor() async {
    final prefs = await SharedPreferences.getInstance();
    _useDynamicColor = prefs.getBool(_dynamicKey) ?? false;
    if (_useDynamicColor) {
      await _loadSystemColor();
    }
    notifyListeners();
  }

  /// 通过 dynamic_color 插件获取 Android 12+ 系统调色板。
  /// 取 palette.primary 的 tone 40 作为种子色（Material 3 中 tone 40 是默认 primary 色）。
  /// 低于 Android 12 返回 null → 自动回退默认种子。
  Future<void> _loadSystemColor() async {
    try {
      final palette = await DynamicColorPlugin.getCorePalette();
      if (palette != null) {
        // CorePalette.primary 是 TonalPalette（非空），用 get(40) 取 ARGB int
        _systemSeedColor = Color(palette.primary.get(40));
      } else {
        _systemSeedColor = null;
      }
    } catch (_) {
      _systemSeedColor = null;
    }
  }

  /// 切换「使用系统主题色」开关。
  Future<void> setUseDynamicColor(bool enabled) async {
    if (_useDynamicColor == enabled) return;
    _useDynamicColor = enabled;
    if (enabled) {
      await _loadSystemColor();
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dynamicKey, enabled);
  }

  /// 加载「预见性返回手势」开关持久化值，默认开启。
  Future<void> _loadPredictiveBack() async {
    final prefs = await SharedPreferences.getInstance();
    _predictiveBackEnabled = prefs.getBool(_predictiveBackKey) ?? true;
    notifyListeners();
  }

  /// 切换「预见性返回手势」开关。
  /// 开启时 PopScope.canPop=true 启用预测动画；关闭时 canPop=false 弹退出确认框。
  Future<void> setPredictiveBackEnabled(bool enabled) async {
    if (_predictiveBackEnabled == enabled) return;
    _predictiveBackEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_predictiveBackKey, enabled);
  }

  void toggleTheme() {
    switch (_themeMode) {
      case ThemeMode.light:
        setThemeMode(ThemeMode.dark);
        break;
      case ThemeMode.dark:
        setThemeMode(ThemeMode.system);
        break;
      case ThemeMode.system:
        setThemeMode(ThemeMode.light);
        break;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _saveThemeMode(mode);
  }
}
