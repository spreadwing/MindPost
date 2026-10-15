import 'package:flutter/material.dart';

/// MindPost 统一字体体系（Plan A: Modern Pro 科技极简风格）
/// - UI 界面字体：Inter（西文/数字）+ HarmonyOS Sans SC / 苹方 / 微软雅黑（中文及标点回退）
/// - 代码/等宽字体：JetBrains Mono + 现代等宽与中文字体兜底
class AppFonts {
  AppFonts._();

  /// 全局 UI 主字体族（西文与数字优先）
  static const String uiFamily = 'Inter';

  /// 全局 UI 字体回退栈（中文与标点）
  static const List<String> uiFallback = [
    'HarmonyOS Sans SC',
    'HarmonyOS Sans',
    'PingFang SC',
    'Microsoft YaHei',
    'Segoe UI',
    'sans-serif',
  ];

  /// 代码、JSON、URL、参数与终端等宽主字体族
  static const String codeFamily = 'JetBrainsMono';

  /// 代码等宽字体回退栈（保证多平台及中文注释一致性）
  static const List<String> codeFallback = [
    'JetBrains Mono',
    'Cascadia Code',
    'Cascadia Mono',
    'Consolas',
    'Menlo',
    'Monaco',
    'monospace',
    'HarmonyOS Sans SC',
    'PingFang SC',
    'Microsoft YaHei',
  ];

  /// 快速构造等宽/代码文本样式
  static TextStyle code({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    FontStyle? fontStyle,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: codeFamily,
      fontFamilyFallback: codeFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      fontStyle: fontStyle,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
      letterSpacing: letterSpacing,
    );
  }
}
