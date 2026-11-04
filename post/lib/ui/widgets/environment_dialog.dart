import 'package:flutter/material.dart';
import '../app_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../models/environment.dart';
import '../../models/workspace.dart';

class EnvironmentDialog extends StatefulWidget {
  final Workspace workspace;
  final VoidCallback onSaved;

  const EnvironmentDialog({
    super.key,
    required this.workspace,
    required this.onSaved,
  });

  @override
  State<EnvironmentDialog> createState() => _EnvironmentDialogState();
}

class _EnvironmentDialogState extends State<EnvironmentDialog> {
  late List<Environment> _environments;
  Environment? _selectedEnv;

  @override
  void initState() {
    super.initState();
    _environments = widget.workspace.environments;
    if (_environments.isNotEmpty) {
      final activeId = widget.workspace.activeEnvironmentId;
      _selectedEnv = _environments.cast<Environment?>().firstWhere(
            (e) => e?.id == activeId,
            orElse: () => _environments.first,
          );
    }
  }

  void _addNewEnvironment() {
    final newEnv = Environment(
      id: const Uuid().v4(),
      name: '新环境 ${_environments.length + 1}',
      variables: [
        VariableItem(
          key: 'baseUrl',
          value: 'https://api.example.com',
          isEnum: true,
          enumOptions: [
            EnumOption(name: '默认网关', value: 'https://api.example.com'),
            EnumOption(name: '本地服务', value: 'http://127.0.0.1:8080'),
          ],
          showInHeader: true,
        ),
        VariableItem(key: 'apiKey', value: 'secret_123', isSecret: true),
      ],
    );
    setState(() {
      _environments.add(newEnv);
      _selectedEnv = newEnv;
    });
  }

  void _deleteCurrentEnvironment() {
    if (_selectedEnv == null) return;
    setState(() {
      _environments.removeWhere((e) => e.id == _selectedEnv!.id);
      if (_environments.isNotEmpty) {
        _selectedEnv = _environments.first;
      } else {
        _selectedEnv = null;
      }
    });
  }

  void _moveVariable(int fromIndex, int toIndex) {
    if (_selectedEnv == null) return;
    final vars = _selectedEnv!.variables;
    if (fromIndex < 0 ||
        fromIndex >= vars.length ||
        toIndex < 0 ||
        toIndex >= vars.length) {
      return;
    }
    setState(() {
      final item = vars.removeAt(fromIndex);
      vars.insert(toIndex, item);
    });
  }

  /// 构建去重后的有效枚举选项列表（按 value 去重）
  List<EnumOption> _getEffectiveEnumOptions(VariableItem item) {
    final Map<String, EnumOption> map = {};
    for (final opt in item.enumOptions) {
      if (opt.value.trim().isNotEmpty && !map.containsKey(opt.value)) {
        map[opt.value] = opt;
      }
    }
    if (item.value.trim().isNotEmpty && !map.containsKey(item.value)) {
      map[item.value] = EnumOption(name: item.value, value: item.value);
    }
    return map.values.toList();
  }

  /// 弹出枚举候选值管理对话框（支持设置枚举名称与实际值、切换当前生效值、排序与删除）
  void _showEnumValuesEditor(VariableItem item) {
    const gridBorder = BorderSide(color: Color(0xFFE2E8F0), width: 1);
    final nameController = TextEditingController();
    final valueController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void addEnumCandidate() {
              final nm = nameController.text.trim();
              final val = valueController.text.trim();
              if (val.isEmpty && nm.isEmpty) return;
              final finalVal = val.isNotEmpty ? val : nm;
              final finalName = nm.isNotEmpty ? nm : finalVal;

              setModalState(() {
                item.enumOptions.add(
                  EnumOption(name: finalName, value: finalVal),
                );
                if (item.value.isEmpty) {
                  item.value = finalVal;
                }
                nameController.clear();
                valueController.clear();
              });
              setState(() {});
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: Container(
                width: 620,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.list_alt_rounded,
                            color: Color(0xFF2563EB), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '枚举项配置 · ${item.key.isEmpty ? "未命名变量" : item.key}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const Divider(height: 16),

                    // 快速新增枚举名称与值输入栏
                    Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: TextField(
                            controller: nameController,
                            style: const TextStyle(fontSize: 12.5),
                            decoration: const InputDecoration(
                              hintText: '枚举名称，如 本地服务',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => addEnumCandidate(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 6,
                          child: TextField(
                            controller: valueController,
                            style: const TextStyle(
                                fontSize: 12.5, fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback),
                            decoration: const InputDecoration(
                              hintText: '枚举值，如 http://127.0.0.1:8080',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => addEnumCandidate(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                          onPressed: addEnumCandidate,
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('添加',
                              style: TextStyle(fontSize: 12.5)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 枚举项编辑表格
                    Container(
                      constraints: const BoxConstraints(maxHeight: 260),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 32,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF1F5F9),
                              border: Border(bottom: gridBorder),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(
                                    border: Border(right: gridBorder),
                                  ),
                                  child: const Text(
                                    '生效',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    alignment: Alignment.centerLeft,
                                    decoration: const BoxDecoration(
                                      border: Border(right: gridBorder),
                                    ),
                                    child: const Text(
                                      '枚举名称',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    alignment: Alignment.centerLeft,
                                    decoration: const BoxDecoration(
                                      border: Border(right: gridBorder),
                                    ),
                                    child: const Text(
                                      '枚举值',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                  width: 42,
                                  child: Center(
                                    child: Text(
                                      '操作',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (item.enumOptions.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 26),
                              child: Center(
                                child: Text(
                                  '暂无枚举项，请在上方输入名称与值后点击添加',
                                  style: TextStyle(
                                      color: Color(0xFF94A3B8), fontSize: 12),
                                ),
                              ),
                            )
                          else
                            Flexible(
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: item.enumOptions.length,
                                itemBuilder: (context, idx) {
                                  final opt = item.enumOptions[idx];
                                  final isCurrent = item.value == opt.value;
                                  return Container(
                                    key: ObjectKey(opt),
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: isCurrent
                                          ? const Color(0xFFEFF6FF)
                                              .withValues(alpha: 0.45)
                                          : Colors.white,
                                      border: const Border(bottom: gridBorder),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        // 选中生效单选框
                                        InkWell(
                                          onTap: () {
                                            setModalState(() {
                                              item.value = opt.value;
                                            });
                                            setState(() {});
                                          },
                                          child: Container(
                                            width: 44,
                                            alignment: Alignment.center,
                                            decoration: const BoxDecoration(
                                              border: Border(right: gridBorder),
                                            ),
                                            child: Icon(
                                              isCurrent
                                                  ? Icons.radio_button_checked
                                                  : Icons
                                                      .radio_button_unchecked,
                                              size: 16,
                                              color: isCurrent
                                                  ? const Color(0xFF2563EB)
                                                  : const Color(0xFF94A3B8),
                                            ),
                                          ),
                                        ),

                                        // 枚举名称输入
                                        Expanded(
                                          flex: 4,
                                          child: Container(
                                            decoration: const BoxDecoration(
                                              border: Border(right: gridBorder),
                                            ),
                                            alignment: Alignment.centerLeft,
                                            child: TextFormField(
                                              key: ValueKey(
                                                  'enum_name_${identityHashCode(opt)}'),
                                              initialValue: opt.name,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: isCurrent
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                color: const Color(0xFF0F172A),
                                              ),
                                              decoration: const InputDecoration(
                                                hintText: '输入枚举名称',
                                                hintStyle: TextStyle(
                                                    color: Color(0xFFCBD5E1),
                                                    fontSize: 11.5),
                                                filled: false,
                                                isDense: true,
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 8),
                                                border: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
                                              ),
                                              onChanged: (val) {
                                                opt.name = val;
                                                setState(() {});
                                              },
                                            ),
                                          ),
                                        ),

                                        // 枚举值输入
                                        Expanded(
                                          flex: 6,
                                          child: Container(
                                            decoration: const BoxDecoration(
                                              border: Border(right: gridBorder),
                                            ),
                                            alignment: Alignment.centerLeft,
                                            child: TextFormField(
                                              key: ValueKey(
                                                  'enum_val_${identityHashCode(opt)}'),
                                              initialValue: opt.value,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
                                                color: Color(0xFF1E293B),
                                              ),
                                              decoration: const InputDecoration(
                                                hintText: '输入枚举值',
                                                hintStyle: TextStyle(
                                                    color: Color(0xFFCBD5E1),
                                                    fontSize: 11.5),
                                                filled: false,
                                                isDense: true,
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 8),
                                                border: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
                                              ),
                                              onChanged: (val) {
                                                final wasCurrent =
                                                    item.value == opt.value;
                                                opt.value = val;
                                                if (wasCurrent) {
                                                  item.value = val;
                                                }
                                                setState(() {});
                                              },
                                            ),
                                          ),
                                        ),

                                        // 删除按钮
                                        SizedBox(
                                          width: 42,
                                          child: Center(
                                            child: IconButton(
                                              tooltip: '移除该枚举项',
                                              icon: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  size: 15,
                                                  color: Color(0xFF94A3B8)),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                  minWidth: 26, minHeight: 26),
                                              onPressed: () {
                                                final wasCurrent =
                                                    item.value == opt.value;
                                                setModalState(() {
                                                  item.enumOptions
                                                      .removeAt(idx);
                                                  if (wasCurrent) {
                                                    item.value = item
                                                            .enumOptions
                                                            .isNotEmpty
                                                        ? item.enumOptions.first
                                                            .value
                                                        : '';
                                                  }
                                                });
                                                setState(() {});
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeTrackColor: const Color(0xFF2563EB),
                      title: const Text(
                        '在软件顶部导航栏显示快速切换',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      value: item.showInHeader,
                      onChanged: (val) {
                        setModalState(() {
                          item.showInHeader = val;
                        });
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 9),
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                        child:
                            const Text('完成', style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        width: 920,
        height: 590,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.public, color: Color(0xFF3B82F6), size: 22),
                const SizedBox(width: 8),
                const Text(
                  '环境变量配置',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 20),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左侧环境列表
                  Container(
                    width: 185,
                    decoration: BoxDecoration(
                      border: Border(
                          right: BorderSide(color: Colors.grey.shade300)),
                    ),
                    padding: const EdgeInsets.only(right: 12),
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            itemCount: _environments.length,
                            itemBuilder: (context, index) {
                              final env = _environments[index];
                              final isSelected = env.id == _selectedEnv?.id;
                              return ListTile(
                                dense: true,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                selected: isSelected,
                                selectedTileColor: const Color(0xFF3B82F6)
                                    .withValues(alpha: 0.12),
                                title: Text(
                                  env.name,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                ),
                                onTap: () {
                                  setState(() {
                                    _selectedEnv = env;
                                  });
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _addNewEnvironment,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('新建环境',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // 右侧环境详情编辑
                  Expanded(
                    child: _selectedEnv == null
                        ? const Center(child: Text('请选择或新建一个环境'))
                        : SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        key: ValueKey(
                                            'name_${_selectedEnv!.id}'),
                                        initialValue: _selectedEnv!.name,
                                        decoration: const InputDecoration(
                                          labelText: '环境名称',
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (val) {
                                          setState(() {
                                            _selectedEnv!.name = val;
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red,
                                        side: BorderSide(
                                            color: Colors.red.shade200),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                      ),
                                      onPressed: _deleteCurrentEnvironment,
                                      icon: const Icon(Icons.delete_outline,
                                          size: 16),
                                      label: const Text('删除环境',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    const Text(
                                      '环境变量列表',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (!_selectedEnv!.variables
                                        .any((v) => v.key.trim() == 'baseUrl'))
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _selectedEnv!.variables.insert(
                                              0,
                                              VariableItem(
                                                key: 'baseUrl',
                                                value:
                                                    'https://api.example.com',
                                                isEnum: true,
                                                enumOptions: [
                                                  EnumOption(
                                                    name: '默认网关',
                                                    value:
                                                        'https://api.example.com',
                                                  ),
                                                  EnumOption(
                                                    name: '本地服务',
                                                    value:
                                                        'http://127.0.0.1:8080',
                                                  ),
                                                ],
                                                showInHeader: true,
                                              ),
                                            );
                                          });
                                        },
                                        icon: const Icon(Icons.add_link_rounded,
                                            size: 15),
                                        label: const Text('快速添加 baseUrl',
                                            style: TextStyle(fontSize: 11.5)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                _buildVariablesTable(),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    TextButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _selectedEnv!.variables.add(
                                            VariableItem(key: '', value: ''),
                                          );
                                        });
                                      },
                                      icon: const Icon(Icons.add, size: 16),
                                      label: const Text('添加文本变量',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: () {
                                        final newItem = VariableItem(
                                          key: '',
                                          value: '',
                                          isEnum: true,
                                          enumOptions: [],
                                          showInHeader: true,
                                        );
                                        setState(() {
                                          _selectedEnv!.variables.add(newItem);
                                        });
                                      },
                                      icon: const Icon(Icons.list_alt_rounded,
                                          size: 16),
                                      label: const Text('添加枚举变量',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    widget.onSaved();
                    Navigator.of(context).pop();
                  },
                  child: const Text('保存修改'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVariablesTable() {
    const gridBorder = BorderSide(color: Color(0xFFE2E8F0), width: 1);
    final vars = _selectedEnv!.variables;
    final allEnabled = vars.isNotEmpty && vars.every((v) => v.isEnabled);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              border: Border(bottom: gridBorder),
            ),
            child: Row(
              children: [
                // 拖拽排序列头
                Container(
                  width: 30,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    border: Border(right: gridBorder),
                  ),
                  child: const Icon(Icons.swap_vert_rounded,
                      size: 14, color: Color(0xFF64748B)),
                ),
                Container(
                  width: 34,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    border: Border(right: gridBorder),
                  ),
                  child: vars.isEmpty
                      ? const Icon(Icons.check_box_outline_blank_rounded,
                          size: 15, color: Color(0xFFCBD5E1))
                      : Transform.scale(
                          scale: 0.82,
                          child: Checkbox(
                            value: allEnabled,
                            activeColor: const Color(0xFF2563EB),
                            onChanged: (val) {
                              final target = val ?? false;
                              setState(() {
                                for (final v in vars) {
                                  v.isEnabled = target;
                                }
                              });
                            },
                          ),
                        ),
                ),
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    decoration: const BoxDecoration(
                      border: Border(right: gridBorder),
                    ),
                    child: const Text(
                      '变量名',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 78,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    border: Border(right: gridBorder),
                  ),
                  child: const Text(
                    '类型',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    decoration: const BoxDecoration(
                      border: Border(right: gridBorder),
                    ),
                    child: const Text(
                      '变量值 / 枚举名称切换',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 64,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    border: Border(right: gridBorder),
                  ),
                  child: const Text(
                    '顶栏快切',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
                const SizedBox(
                  width: 82,
                  child: Center(
                    child: Text(
                      '排序 / 操作',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (vars.isEmpty)
            Container(
              height: 44,
              alignment: Alignment.center,
              child: const Text(
                '暂无自定义环境变量，点击下方添加',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: vars.length,
              onReorderItem: (oldIndex, newIndex) =>
                  _moveVariable(oldIndex, newIndex),
              itemBuilder: (context, index) {
                final item = vars[index];
                final validEnumOptions = _getEffectiveEnumOptions(item);

                return Container(
                  key: ObjectKey(item),
                  height: 38,
                  decoration: BoxDecoration(
                    color: item.isEnabled
                        ? Colors.white
                        : const Color(0xFFF8FAFC),
                    border: const Border(bottom: gridBorder),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 0. 拖拽排序手柄
                      ReorderableDragStartListener(
                        index: index,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Container(
                            width: 30,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              border: Border(right: gridBorder),
                            ),
                            child: const Icon(
                              Icons.drag_indicator_rounded,
                              size: 15,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ),

                      // 1. 启用勾选
                      Container(
                        width: 34,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          border: Border(right: gridBorder),
                        ),
                        child: Transform.scale(
                          scale: 0.82,
                          child: Checkbox(
                            value: item.isEnabled,
                            activeColor: const Color(0xFF2563EB),
                            onChanged: (val) {
                              setState(() {
                                item.isEnabled = val ?? true;
                              });
                            },
                          ),
                        ),
                      ),

                      // 2. 变量名
                      Expanded(
                        flex: 3,
                        child: Container(
                          decoration: const BoxDecoration(
                            border: Border(right: gridBorder),
                          ),
                          alignment: Alignment.centerLeft,
                          child: TextFormField(
                            key: ValueKey('env_key_${identityHashCode(item)}'),
                            initialValue: item.key,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: const InputDecoration(
                              hintText: '如 baseUrl',
                              hintStyle: TextStyle(
                                  color: Color(0xFFCBD5E1), fontSize: 12),
                              filled: false,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                            onChanged: (val) => item.key = val,
                          ),
                        ),
                      ),

                      // 3. 变量类型切换 (文本 / 枚举)
                      Container(
                        width: 78,
                        decoration: const BoxDecoration(
                          border: Border(right: gridBorder),
                        ),
                        alignment: Alignment.center,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () {
                            setState(() {
                              item.isEnum = !item.isEnum;
                              if (item.isEnum) {
                                final trimmed = item.value.trim();
                                if (trimmed.isNotEmpty &&
                                    !item.enumOptions
                                        .any((o) => o.value == trimmed)) {
                                  item.enumOptions.add(
                                    EnumOption(name: trimmed, value: trimmed),
                                  );
                                }
                              } else {
                                item.showInHeader = false;
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: item.isEnum
                                  ? const Color(0xFFEFF6FF)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: item.isEnum
                                    ? const Color(0xFFBFDBFE)
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  item.isEnum
                                      ? Icons.list_alt_rounded
                                      : Icons.text_fields_rounded,
                                  size: 12,
                                  color: item.isEnum
                                      ? const Color(0xFF2563EB)
                                      : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  item.isEnum ? '枚举' : '文本',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: item.isEnum
                                        ? const Color(0xFF2563EB)
                                        : const Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // 4. 变量值 / 枚举名称下拉切换与配置
                      Expanded(
                        flex: 6,
                        child: Container(
                          decoration: const BoxDecoration(
                            border: Border(right: gridBorder),
                          ),
                          alignment: Alignment.centerLeft,
                          child: item.isEnum
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: validEnumOptions.isEmpty
                                            ? InkWell(
                                                onTap: () =>
                                                    _showEnumValuesEditor(item),
                                                child: const Text(
                                                  '点击右侧配置枚举名称与值...',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF94A3B8),
                                                  ),
                                                ),
                                              )
                                            : DropdownButtonHideUnderline(
                                                child: DropdownButton<String>(
                                                  value: validEnumOptions.any(
                                                          (o) =>
                                                              o.value ==
                                                              item.value)
                                                      ? item.value
                                                      : validEnumOptions
                                                          .first.value,
                                                  isExpanded: true,
                                                  isDense: true,
                                                  icon: const Icon(
                                                    Icons
                                                        .keyboard_arrow_down_rounded,
                                                    size: 16,
                                                    color: Color(0xFF2563EB),
                                                  ),
                                                  style: const TextStyle(
                                                    fontSize: 12.5,
                                                    color: Color(0xFF0F172A),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  items: validEnumOptions
                                                      .map((opt) {
                                                    return DropdownMenuItem<
                                                        String>(
                                                      value: opt.value,
                                                      child: Text(
                                                        opt.displayLabel,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    );
                                                  }).toList(),
                                                  onChanged: (val) {
                                                    if (val != null) {
                                                      setState(() {
                                                        item.value = val;
                                                      });
                                                    }
                                                  },
                                                ),
                                              ),
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(4),
                                        onTap: () =>
                                            _showEnumValuesEditor(item),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8FAFC),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                                color:
                                                    const Color(0xFFCBD5E1)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.tune_rounded,
                                                  size: 12,
                                                  color: Color(0xFF2563EB)),
                                              const SizedBox(width: 3),
                                              Text(
                                                '枚举 · ${item.enumOptions.length}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF2563EB),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        key: ValueKey(
                                            'env_val_${identityHashCode(item)}_${item.value}'),
                                        initialValue: item.value,
                                        obscureText: item.isSecret,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
                                        ),
                                        decoration: const InputDecoration(
                                          hintText: '输入变量值',
                                          hintStyle: TextStyle(
                                              color: Color(0xFFCBD5E1),
                                              fontSize: 12),
                                          filled: false,
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 8),
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                        ),
                                        onChanged: (val) => item.value = val,
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        item.isSecret
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 15,
                                        color: const Color(0xFF64748B),
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                          minWidth: 28, minHeight: 28),
                                      tooltip:
                                          item.isSecret ? '显示明文' : '隐藏敏感值',
                                      onPressed: () {
                                        setState(() {
                                          item.isSecret = !item.isSecret;
                                        });
                                      },
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                ),
                        ),
                      ),

                      // 5. 顶栏快切开关
                      Container(
                        width: 64,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          border: Border(right: gridBorder),
                        ),
                        child: Tooltip(
                          message: '在软件上方显示并快速切换枚举',
                          child: Transform.scale(
                            scale: 0.82,
                            child: Checkbox(
                              value: item.isEnum && item.showInHeader,
                              activeColor: const Color(0xFF2563EB),
                              onChanged: (val) {
                                final target = val ?? false;
                                setState(() {
                                  if (target && !item.isEnum) {
                                    item.isEnum = true;
                                    final trimmed = item.value.trim();
                                    if (trimmed.isNotEmpty &&
                                        !item.enumOptions
                                            .any((o) => o.value == trimmed)) {
                                      item.enumOptions.add(
                                        EnumOption(
                                            name: trimmed, value: trimmed),
                                      );
                                    }
                                  }
                                  item.showInHeader = target;
                                });
                              },
                            ),
                          ),
                        ),
                      ),

                      // 6. 上移 / 下移 / 删除操作
                      SizedBox(
                        width: 82,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: '上移',
                              icon: Icon(
                                Icons.arrow_upward_rounded,
                                size: 14,
                                color: index > 0
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFFCBD5E1),
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 24, minHeight: 26),
                              onPressed: index > 0
                                  ? () => _moveVariable(index, index - 1)
                                  : null,
                            ),
                            IconButton(
                              tooltip: '下移',
                              icon: Icon(
                                Icons.arrow_downward_rounded,
                                size: 14,
                                color: index < vars.length - 1
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFFCBD5E1),
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 24, minHeight: 26),
                              onPressed: index < vars.length - 1
                                  ? () => _moveVariable(index, index + 1)
                                  : null,
                            ),
                            IconButton(
                              tooltip: '删除变量',
                              icon: const Icon(Icons.delete_outline_rounded,
                                  size: 15),
                              color: const Color(0xFF94A3B8),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 24, minHeight: 26),
                              onPressed: () {
                                setState(() {
                                  vars.removeAt(index);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
