import 'package:flutter/material.dart';

/// 现代下拉菜单项配置
class ModernDropdownItem<T> {
  final T value;
  final String label;
  final Widget? icon;
  final Widget? customContent;

  const ModernDropdownItem({
    required this.value,
    required this.label,
    this.icon,
    this.customContent,
  });
}

/// 现代极简扁平下拉选择器
///
/// 相比原生 Flutter DropdownButton 的粗重 Material 样式与突兀灰块选中态，
/// 本组件基于 PopupMenu 实现，具有以下现代工程桌面规范：
/// 1. 弹出于触发器正下方（留出 4px 呼吸间距），不遮挡按钮头部；
/// 2. 纯白底色配合 1px Slate-200 (0xFFE2E8F0) 边框与 8px 圆角；
/// 3. 极柔和的微景深投影，杜绝浓重黑灰阴影；
/// 4. 紧凑菜单项（高度 32px），选中项浅蓝底色 + 品牌蓝字体 + 右侧勾选图标；
/// 5. 悬浮微动效与顺畅交互体验。
class ModernDropdown<T> extends StatelessWidget {
  final T value;
  final List<ModernDropdownItem<T>> items;
  final ValueChanged<T> onChanged;
  final Widget child;
  final double? menuWidth;
  final String? tooltip;

  const ModernDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.child,
    this.menuWidth,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 5,
          shadowColor: const Color(0xFF0F172A).withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
          ),
          menuPadding: const EdgeInsets.symmetric(vertical: 4),
        ),
      ),
      child: PopupMenuButton<T>(
        tooltip: tooltip,
        initialValue: value,
        position: PopupMenuPosition.under,
        offset: const Offset(0, 4),
        padding: EdgeInsets.zero,
        constraints: BoxConstraints(
          minWidth: menuWidth ?? 130,
          maxWidth: 280,
        ),
        onSelected: onChanged,
        itemBuilder: (context) {
          return items.map((item) {
            final isSelected = item.value == value;

            return PopupMenuItem<T>(
              value: item.value,
              height: 34,
              padding: EdgeInsets.zero,
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                color: isSelected
                    ? const Color(0xFFF1F5F9)
                    : Colors.transparent,
                child: Row(
                  children: [
                    if (item.icon != null) ...[
                      item.icon!,
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: item.customContent ??
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isSelected
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: Color(0xFF2563EB),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList();
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: child,
        ),
      ),
    );
  }
}
