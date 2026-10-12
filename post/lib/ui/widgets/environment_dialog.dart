import 'package:flutter/material.dart';
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
      baseUrl: 'https://api.example.com',
      variables: [
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        width: 820,
        height: 560,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.public, color: Color(0xFF3B82F6), size: 22),
                const SizedBox(width: 8),
                const Text(
                  '环境变量与 URL 前缀配置',
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
                    width: 200,
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: Colors.grey.shade300)),
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
                                selectedTileColor:
                                    const Color(0xFF3B82F6).withValues(alpha: 0.12),
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
                            label: const Text('新建环境', style: TextStyle(fontSize: 12)),
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
                                      flex: 4,
                                      child: TextFormField(
                                        key: ValueKey('name_${_selectedEnv!.id}'),
                                        initialValue: _selectedEnv!.name,
                                        decoration: const InputDecoration(
                                          labelText: '环境名称',
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (val) {
                                          _selectedEnv!.name = val;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 6,
                                      child: TextFormField(
                                        key: ValueKey('baseUrl_${_selectedEnv!.id}'),
                                        initialValue: _selectedEnv!.baseUrl,
                                        decoration: const InputDecoration(
                                          labelText: '默认 Base URL 前缀 (如 https://api.dev.com)',
                                          hintText: 'https://...',
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (val) {
                                          _selectedEnv!.baseUrl = val;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
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
                                    IconButton(
                                      tooltip: '删除当前环境',
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      onPressed: _deleteCurrentEnvironment,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                _buildVariablesTable(),
                                const SizedBox(height: 12),
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _selectedEnv!.variables.add(
                                        VariableItem(key: '', value: ''),
                                      );
                                    });
                                  },
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('添加环境变量', style: TextStyle(fontSize: 12)),
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
    if (_selectedEnv!.variables.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        alignment: Alignment.center,
        child: Text(
          '暂无自定义变量，点击下方添加',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _selectedEnv!.variables.length,
      itemBuilder: (context, index) {
        final item = _selectedEnv!.variables[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            children: [
              Checkbox(
                value: item.isEnabled,
                onChanged: (val) {
                  setState(() {
                    item.isEnabled = val ?? true;
                  });
                },
              ),
              Expanded(
                flex: 4,
                child: TextFormField(
                  initialValue: item.key,
                  decoration: const InputDecoration(
                    hintText: 'Variable Name',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) => item.key = val,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: TextFormField(
                  initialValue: item.value,
                  obscureText: item.isSecret,
                  decoration: InputDecoration(
                    hintText: 'Value',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        item.isSecret
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 16,
                      ),
                      onPressed: () {
                        setState(() {
                          item.isSecret = !item.isSecret;
                        });
                      },
                    ),
                  ),
                  onChanged: (val) => item.value = val,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: Colors.red.shade400,
                onPressed: () {
                  setState(() {
                    _selectedEnv!.variables.removeAt(index);
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
