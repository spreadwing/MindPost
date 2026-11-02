// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/window_manager.dart';

/// 系统托盘与桌面窗口生命周期管理服务
class TrayWindowService with WindowListener, TrayListener {
  TrayWindowService._();
  static final TrayWindowService instance = TrayWindowService._();

  bool _initialized = false;
  bool _isExiting = false;

  /// 回调函数：返回当前工作区是否开启了关闭时缩小到托盘
  bool Function()? shouldMinimizeToTray;

  /// 回调函数：当应用缩小到托盘时通知外部（例如显示提示等）
  VoidCallback? onMinimizedToTray;

  /// 回调函数：窗口关闭或退出前触发（用于持久化状态等）
  FutureOr<void> Function()? onBeforeClose;

  bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  Future<void> init({
    bool Function()? shouldMinimizeToTray,
    VoidCallback? onMinimizedToTray,
    FutureOr<void> Function()? onBeforeClose,
  }) async {
    if (!isSupported || _initialized) return;
    this.shouldMinimizeToTray = shouldMinimizeToTray;
    this.onMinimizedToTray = onMinimizedToTray;
    this.onBeforeClose = onBeforeClose;

    try {
      // 1. 初始化 windowManager 监听并拦截系统原生关闭行为
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
    } catch (e) {
      debugPrint('[TrayWindowService] windowManager 初始化异常: $e');
    }

    try {
      // 2. 初始化托盘图标与上下文菜单
      trayManager.addListener(this);
      await _initSystemTray();
    } catch (e) {
      debugPrint('[TrayWindowService] trayManager 初始化异常: $e');
    }

    _initialized = true;
  }

  Future<void> _initSystemTray() async {
    try {
      final iconPath = _resolveTrayIconPath();
      if (iconPath != null) {
        await trayManager.setIcon(iconPath);
      }
      await trayManager
          .setToolTip('MindPost - AI-Native API Workbench\n点击恢复窗口，右键弹出菜单');

      final menu = Menu(
        items: [
          MenuItem(
            key: 'show_window',
            label: '显示 MindPost',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'exit_app',
            label: '退出 MindPost',
          ),
        ],
      );
      await trayManager.setContextMenu(menu);
    } catch (e) {
      debugPrint('[TrayWindowService] 初始化系统托盘失败: $e');
    }
  }

  String? _resolveTrayIconPath() {
    if (Platform.isWindows) {
      // 1. 优先检查打包安装后的 flutter_assets 目录
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final installedIco =
          p.join(exeDir, 'data', 'flutter_assets', 'assets', 'app_icon.ico');
      if (File(installedIco).existsSync()) {
        return installedIco;
      }
      // 2. 检查当前运行工作目录下的 assets
      final localIco = p.join(Directory.current.path, 'assets', 'app_icon.ico');
      if (File(localIco).existsSync()) {
        return localIco;
      }
      // 3. 检查 windows runner resources 目录
      final runnerIco = p.join(Directory.current.path, 'windows', 'runner',
          'resources', 'app_icon.ico');
      if (File(runnerIco).existsSync()) {
        return runnerIco;
      }
      // 兜底返回相对 asset 路径
      return 'assets/app_icon.ico';
    } else {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final installedPng =
          p.join(exeDir, 'data', 'flutter_assets', 'assets', 'app_logo.png');
      if (File(installedPng).existsSync()) {
        return installedPng;
      }
      final localPng = p.join(Directory.current.path, 'assets', 'app_logo.png');
      if (File(localPng).existsSync()) {
        return localPng;
      }
      return 'assets/app_logo.png';
    }
  }

  // ---------------- WindowListener ----------------

  @override
  void onWindowClose() async {
    if (_isExiting) return;

    try {
      await onBeforeClose?.call();
    } catch (e) {
      debugPrint('[TrayWindowService] onBeforeClose 执行异常: $e');
    }

    final shouldMin = shouldMinimizeToTray?.call() ?? true;
    if (shouldMin) {
      await hideToTray();
    } else {
      await exitApp();
    }
  }

  // ---------------- TrayListener ----------------

  @override
  void onTrayIconMouseDown() async {
    // 鼠标左键点击托盘图标：智能恢复或切换前台窗口
    await handleTrayClick();
  }

  @override
  void onTrayIconRightMouseDown() async {
    // 鼠标右键点击托盘图标：弹出上下文菜单
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show_window':
        await showWindow();
        break;
      case 'exit_app':
        await exitApp();
        break;
    }
  }

  // ---------------- Actions ----------------

  /// 缩小隐藏到系统托盘
  Future<void> hideToTray() async {
    if (!isSupported) return;
    try {
      await windowManager.hide();
    } catch (e) {
      debugPrint('[TrayWindowService] 隐藏窗口失败: $e');
    } finally {
      onMinimizedToTray?.call();
    }
  }

  /// 恢复并激活窗口
  Future<void> showWindow() async {
    if (!isSupported) return;
    try {
      final isMinimized = await windowManager.isMinimized();
      if (isMinimized) {
        await windowManager.restore();
      }
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('[TrayWindowService] 显示窗口失败: $e');
    }
  }

  /// 托盘左键点击处理：未显示则显示，后台则激活，前台激活则最小化
  Future<void> handleTrayClick() async {
    if (!isSupported) return;
    try {
      final isVisible = await windowManager.isVisible();
      if (!isVisible) {
        await showWindow();
        return;
      }
      final isMinimized = await windowManager.isMinimized();
      if (isMinimized) {
        await showWindow();
        return;
      }
      final isFocused = await windowManager.isFocused();
      if (isFocused) {
        await hideToTray();
      } else {
        await showWindow();
      }
    } catch (e) {
      debugPrint('[TrayWindowService] 切换窗口状态失败: $e');
      await showWindow();
    }
  }

  /// 完全退出应用程序
  Future<void> exitApp() async {
    if (_isExiting) return;
    _isExiting = true;
    try {
      await onBeforeClose?.call();
    } catch (e) {
      debugPrint('[TrayWindowService] 退出前保存状态异常: $e');
    }
    Timer.run(() async {
      try {
        windowManager.removeListener(this);
        trayManager.removeListener(this);
        await windowManager.setPreventClose(false);
        await trayManager.destroy();
        await windowManager.destroy();
      } catch (e) {
        debugPrint('[TrayWindowService] 退出程序异常: $e');
      } finally {
        exit(0);
      }
    });
  }

  void dispose() {
    if (!isSupported) return;
    windowManager.removeListener(this);
    trayManager.removeListener(this);
  }
}
