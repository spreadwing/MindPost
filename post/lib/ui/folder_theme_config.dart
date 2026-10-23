import 'package:flutter/material.dart';

/// 文件夹图标形态
enum FolderIconStyle {
  duotone('duotone', '双色调', Icons.folder_copy_outlined),
  outlined('outlined', '纯线性', Icons.folder_outlined),
  filled('filled', '经典实心', Icons.folder_rounded);

  final String id;
  final String label;
  final IconData icon;

  const FolderIconStyle(this.id, this.label, this.icon);

  static FolderIconStyle fromId(String? id) {
    return FolderIconStyle.values.firstWhere(
      (e) => e.id == id,
      orElse: () => FolderIconStyle.duotone,
    );
  }
}

/// 文件夹配色方案预设
class FolderColorPreset {
  final String id;
  final String name;
  final Color primaryColor;
  final double duotoneOpacity;
  final bool isSystem;

  const FolderColorPreset({
    required this.id,
    required this.name,
    required this.primaryColor,
    required this.duotoneOpacity,
    this.isSystem = false,
  });

  /// 获取在当前上下文中的实际有效主色
  Color resolveColor(BuildContext context) {
    if (isSystem) {
      return Theme.of(context).colorScheme.primary;
    }
    return primaryColor;
  }

  /// 预设配色方案列表
  static const List<FolderColorPreset> presets = [
    FolderColorPreset(
      id: 'blue',
      name: '柔和科技蓝',
      primaryColor: Color(0xFF3B82F6),
      duotoneOpacity: 0.15,
    ),
    FolderColorPreset(
      id: 'amber',
      name: '经典琥珀橙',
      primaryColor: Color(0xFFF59E0B),
      duotoneOpacity: 0.18,
    ),
    FolderColorPreset(
      id: 'slate',
      name: '极简中性灰',
      primaryColor: Color(0xFF64748B),
      duotoneOpacity: 0.12,
    ),
    FolderColorPreset(
      id: 'emerald',
      name: '清新翡翠绿',
      primaryColor: Color(0xFF10B981),
      duotoneOpacity: 0.15,
    ),
    FolderColorPreset(
      id: 'purple',
      name: '优雅幻影紫',
      primaryColor: Color(0xFF8B5CF6),
      duotoneOpacity: 0.15,
    ),
    FolderColorPreset(
      id: 'system',
      name: '跟随系统主色',
      primaryColor: Color(0xFF2563EB),
      duotoneOpacity: 0.15,
      isSystem: true,
    ),
  ];

  static FolderColorPreset fromId(String? id) {
    return presets.firstWhere(
      (e) => e.id == id,
      orElse: () => presets.first, // 默认推荐：柔和科技蓝
    );
  }
}

/// 文件夹主题配置扩展（ThemeExtension）
@immutable
class FolderThemeConfig extends ThemeExtension<FolderThemeConfig> {
  final FolderColorPreset colorPreset;
  final FolderIconStyle iconStyle;

  const FolderThemeConfig({
    required this.colorPreset,
    required this.iconStyle,
  });

  /// 默认配置：柔和科技蓝 + 双色调
  factory FolderThemeConfig.standard() {
    return const FolderThemeConfig(
      colorPreset: FolderColorPreset(
        id: 'blue',
        name: '柔和科技蓝',
        primaryColor: Color(0xFF3B82F6),
        duotoneOpacity: 0.15,
      ),
      iconStyle: FolderIconStyle.duotone,
    );
  }

  @override
  FolderThemeConfig copyWith({
    FolderColorPreset? colorPreset,
    FolderIconStyle? iconStyle,
  }) {
    return FolderThemeConfig(
      colorPreset: colorPreset ?? this.colorPreset,
      iconStyle: iconStyle ?? this.iconStyle,
    );
  }

  @override
  FolderThemeConfig lerp(ThemeExtension<FolderThemeConfig>? other, double t) {
    if (other is! FolderThemeConfig) return this;
    return t < 0.5 ? this : other;
  }

  static FolderThemeConfig of(BuildContext context) {
    final ext = Theme.of(context).extension<FolderThemeConfig>();
    return ext ?? FolderThemeConfig.standard();
  }
}

/// 渲染可配置文件夹图标的通用控件
class FolderThemeIcon extends StatelessWidget {
  final bool isExpanded;
  final double size;
  final FolderThemeConfig? config;

  const FolderThemeIcon({
    super.key,
    required this.isExpanded,
    this.size = 15.0,
    this.config,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveConfig = config ?? FolderThemeConfig.of(context);
    final color = effectiveConfig.colorPreset.resolveColor(context);
    final opacity = effectiveConfig.colorPreset.duotoneOpacity;

    switch (effectiveConfig.iconStyle) {
      case FolderIconStyle.outlined:
        return Icon(
          isExpanded
              ? Icons.folder_open_outlined
              : Icons.folder_outlined,
          size: size,
          color: color,
        );

      case FolderIconStyle.filled:
        return Icon(
          isExpanded
              ? Icons.folder_open_rounded
              : Icons.folder_rounded,
          size: size,
          color: color,
        );

      case FolderIconStyle.duotone:
        // 双层 Stack 叠加渲染：底层半透明实心色块 + 顶层 100% 主色线性描边
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 底层半透明填充实心图标
              Icon(
                isExpanded
                    ? Icons.folder_open_rounded
                    : Icons.folder_rounded,
                size: size,
                color: color.withValues(alpha: opacity),
              ),
              // 顶层 100% 主色纯线性描边图标
              Icon(
                isExpanded
                    ? Icons.folder_open_outlined
                    : Icons.folder_outlined,
                size: size,
                color: color,
              ),
            ],
          ),
        );
    }
  }
}
