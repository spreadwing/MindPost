import 'package:flutter/material.dart';
import '../../models/api_request.dart';
import '../../models/environment.dart';
import 'key_value_editor.dart';
import 'json_syntax_highlighter.dart';

/// 嵌入在主工作区 Tab 页内的目录公共配置、参数与脚本视图
class ContainerSettingsView extends StatefulWidget {
  final dynamic container; // ApiCollection 或 ApiFolder
  final bool isCollection;
  final VoidCallback? onChanged;
  final VoidCallback onSaved;

  const ContainerSettingsView({
    super.key,
    required this.container,
    this.isCollection = true,
    this.onChanged,
    required this.onSaved,
  });

  @override
  State<ContainerSettingsView> createState() => _ContainerSettingsViewState();
}

class _ContainerSettingsViewState extends State<ContainerSettingsView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late JsSyntaxHighlightController _preScriptController;
  late JsSyntaxHighlightController _postScriptController;

  late List<KeyValueItem> _headers;
  late List<VariableItem> _variables;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _initControllers();
  }

  void _initControllers() {
    _nameController =
        TextEditingController(text: widget.container.name as String? ?? '');
    _descController = TextEditingController(
        text: widget.container.description as String? ?? '');
    _preScriptController = JsSyntaxHighlightController(
        text: widget.container.preRequestScript as String? ?? '');
    _postScriptController = JsSyntaxHighlightController(
        text: widget.container.postRequestScript as String? ?? '');

    _headers = widget.container.headers as List<KeyValueItem>;
    _variables = widget.container.variables as List<VariableItem>;
  }

  @override
  void didUpdateWidget(covariant ContainerSettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.container as dynamic).id !=
        (widget.container as dynamic).id) {
      _nameController.dispose();
      _descController.dispose();
      _preScriptController.dispose();
      _postScriptController.dispose();
      _initControllers();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _preScriptController.dispose();
    _postScriptController.dispose();
    super.dispose();
  }

  /// 实时同步表单与脚本内容到目录模型并标记当前标签为已修改
  void _syncToModel() {
    final trimmedName = _nameController.text.trim();
    if (trimmedName.isNotEmpty) {
      widget.container.name = trimmedName;
    }
    widget.container.description = _descController.text.trim();
    widget.container.preRequestScript = _preScriptController.text;
    widget.container.postRequestScript = _postScriptController.text;
    if (widget.onChanged != null) {
      widget.onChanged!();
    } else {
      widget.onSaved();
    }
  }

  void _saveWithFeedback() {
    if (_nameController.text.trim().isEmpty) {
      _nameController.text = '未命名目录';
    }
    _syncToModel();
    widget.onSaved();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已保存目录【${widget.container.name}】的参数与公共脚本配置'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _insertScriptSnippet(TextEditingController controller, String snippet) {
    final current = controller.text;
    final prefix = current.trim().isEmpty ? '' : '$current\n\n';
    controller.text = '$prefix$snippet';
    _syncToModel();
    setState(() {});
  }

  Widget _buildTabItem(String label, {int count = 0, Color? dotColor}) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE), width: 0.5),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2563EB),
                ),
              ),
            ),
          ] else if (dotColor != null) ...[
            const SizedBox(width: 5),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabledVarCount =
        _variables.where((v) => v.isEnabled && v.key.trim().isNotEmpty).length;
    final enabledHeaderCount =
        _headers.where((h) => h.isEnabled && h.key.trim().isNotEmpty).length;
    final hasPreScript = _preScriptController.text.trim().isNotEmpty;
    final hasPostScript = _postScriptController.text.trim().isNotEmpty;

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部目录标题栏与保存按钮
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Icon(
                    Icons.folder_rounded,
                    color: Color(0xFFF59E0B),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.container.name as String,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: const Color(0xFFBFDBFE), width: 0.8),
                            ),
                            child: const Text(
                              '目录公共配置',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        '在此配置的目录参数、公共 Headers 和前后置脚本，将自顶向下自动继承给其下所有目录与 API 请求',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _saveWithFeedback,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('保存配置'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),

          // 子选项卡栏
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: const Color(0xFF2563EB),
              unselectedLabelColor: const Color(0xFF64748B),
              indicatorColor: const Color(0xFF2563EB),
              indicatorWeight: 2,
              labelStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
              tabs: [
                _buildTabItem('公共 Headers', count: enabledHeaderCount),
                _buildTabItem('目录参数', count: enabledVarCount),
                _buildTabItem(
                  '⚡ 公共前置脚本',
                  dotColor: hasPreScript ? const Color(0xFFF59E0B) : null,
                ),
                _buildTabItem(
                  '🧪 公共后置断言',
                  dotColor: hasPostScript ? const Color(0xFF10B981) : null,
                ),
                _buildTabItem('目录信息'),
              ],
            ),
          ),

          // 内容区
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 1. 公共 Headers
                _buildHeadersTab(),

                // 2. 目录级变量/参数
                _buildVariablesTab(),

                // 3. 公共前置脚本
                _buildPreScriptTab(),

                // 4. 公共后置断言脚本
                _buildPostScriptTab(),

                // 5. 目录基础信息
                _buildInfoTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Tab 1: 公共 Headers
  Widget _buildHeadersTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 15, color: Color(0xFF2563EB)),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '在此配置的公共 Header 会自动附加到该目录下的所有 API 请求中。若下级目录或单接口存在同名 Header，则以子级为准覆盖。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _headers.add(KeyValueItem(key: '', value: ''));
                  });
                  _syncToModel();
                },
                icon: const Icon(Icons.add_rounded, size: 15),
                label:
                    const Text('添加公共 Header', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2563EB),
                  side: const BorderSide(color: Color(0xFFBFDBFE)),
                  backgroundColor: const Color(0xFFEFF6FF),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: KeyValueEditor(
                items: _headers,
                onChanged: () {
                  setState(() {});
                  _syncToModel();
                },
                keyPlaceholder: 'Header 名称，如 Authorization / X-Module',
                valuePlaceholder: 'Header 数值，如 Bearer {{apiKey}}',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Tab 2: 目录参数
  Widget _buildVariablesTab() {
    const gridBorder = BorderSide(color: Color(0xFFE2E8F0), width: 1);
    final allEnabled =
        _variables.isNotEmpty && _variables.every((v) => v.isEnabled);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.data_object_rounded,
                  size: 15, color: Color(0xFF2563EB)),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '定义当前目录作用域内的公共参数变量，下属接口可在 URL、Params、Header 或 Body 中通过 {{变量名}} 直接引用。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _variables.add(VariableItem(key: '', value: ''));
                  });
                  _syncToModel();
                },
                icon: const Icon(Icons.add_rounded, size: 15),
                label: const Text('添加目录参数', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2563EB),
                  side: const BorderSide(color: Color(0xFFBFDBFE)),
                  backgroundColor: const Color(0xFFEFF6FF),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 表头行
                    Container(
                      height: 34,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        border: Border(bottom: gridBorder),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              border: Border(right: gridBorder),
                            ),
                            child: _variables.isEmpty
                                ? const Icon(
                                    Icons.check_box_outline_blank_rounded,
                                    size: 15,
                                    color: Color(0xFFCBD5E1))
                                : Transform.scale(
                                    scale: 0.82,
                                    child: Checkbox(
                                      value: allEnabled,
                                      activeColor: const Color(0xFF2563EB),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(3.5)),
                                      onChanged: (val) {
                                        final target = val ?? false;
                                        setState(() {
                                          for (final v in _variables) {
                                            v.isEnabled = target;
                                          }
                                        });
                                        _syncToModel();
                                      },
                                    ),
                                  ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              alignment: Alignment.centerLeft,
                              decoration: const BoxDecoration(
                                border: Border(right: gridBorder),
                              ),
                              child: const Text(
                                '参数名',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              alignment: Alignment.centerLeft,
                              decoration: const BoxDecoration(
                                border: Border(right: gridBorder),
                              ),
                              child: const Text(
                                '参数值',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              alignment: Alignment.centerLeft,
                              decoration: const BoxDecoration(
                                border: Border(right: gridBorder),
                              ),
                              child: const Text(
                                '参数说明',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: 40,
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

                    // 数据行
                    if (_variables.isEmpty)
                      Container(
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(bottom: gridBorder),
                        ),
                        alignment: Alignment.center,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.table_rows_outlined,
                                size: 15, color: Color(0xFF94A3B8)),
                            SizedBox(width: 6),
                            Text(
                              '暂无目录级公共参数，点击下方「+ 添加一行目录参数」直接在表格中录入',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      for (int i = 0; i < _variables.length; i++)
                        Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: _variables[i].isEnabled
                                ? Colors.white
                                : const Color(0xFFF8FAFC),
                            border: const Border(bottom: gridBorder),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                width: 38,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                  border: Border(right: gridBorder),
                                ),
                                child: Transform.scale(
                                  scale: 0.82,
                                  child: Checkbox(
                                    value: _variables[i].isEnabled,
                                    activeColor: const Color(0xFF2563EB),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(3.5)),
                                    onChanged: (val) {
                                      setState(() {
                                        _variables[i].isEnabled = val ?? true;
                                      });
                                      _syncToModel();
                                    },
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    border: Border(right: gridBorder),
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: TextFormField(
                                    key: ValueKey(
                                        'dir_var_key_${_variables[i].hashCode}_$i'),
                                    initialValue: _variables[i].key,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontFamily: 'Consolas',
                                      fontWeight: FontWeight.w500,
                                      color: _variables[i].isEnabled
                                          ? const Color(0xFF0F172A)
                                          : const Color(0xFF94A3B8),
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: '变量名，如 modulePath',
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
                                    onChanged: (val) {
                                      _variables[i].key = val;
                                      setState(() {});
                                      _syncToModel();
                                    },
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 4,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    border: Border(right: gridBorder),
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: TextFormField(
                                    key: ValueKey(
                                        'dir_var_val_${_variables[i].hashCode}_$i'),
                                    initialValue: _variables[i].value,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontFamily: 'Consolas',
                                      color: _variables[i].isEnabled
                                          ? const Color(0xFF0F172A)
                                          : const Color(0xFF94A3B8),
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: '变量值，如 /api/v1/auth',
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
                                    onChanged: (val) {
                                      _variables[i].value = val;
                                      _syncToModel();
                                    },
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    border: Border(right: gridBorder),
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: TextFormField(
                                    key: ValueKey(
                                        'dir_var_desc_${_variables[i].hashCode}_$i'),
                                    initialValue: _variables[i].description,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _variables[i].isEnabled
                                          ? const Color(0xFF475569)
                                          : const Color(0xFF94A3B8),
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: '可选说明...',
                                      hintStyle: TextStyle(
                                          color: Color(0xFFCBD5E1),
                                          fontSize: 11.5),
                                      filled: false,
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                    ),
                                    onChanged: (val) {
                                      _variables[i].description = val;
                                      _syncToModel();
                                    },
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 40,
                                child: Center(
                                  child: IconButton(
                                    icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 16),
                                    color: const Color(0xFF94A3B8),
                                    hoverColor: const Color(0xFFFEE2E2),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 28, minHeight: 28),
                                    tooltip: '删除此参数',
                                    onPressed: () {
                                      setState(() {
                                        _variables.removeAt(i);
                                      });
                                      _syncToModel();
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                    // 表格底部新增栏
                    Material(
                      color: const Color(0xFFF8FAFC),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _variables.add(VariableItem(key: '', value: ''));
                          });
                          _syncToModel();
                        },
                        child: Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.add_rounded,
                                  size: 15, color: Color(0xFF2563EB)),
                              const SizedBox(width: 4),
                              const Text(
                                '添加一行目录参数',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2563EB),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '共 ${_variables.length} 项 · 已启用 ${_variables.where((v) => v.isEnabled && v.key.trim().isNotEmpty).length} 项',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Tab 3: 公共前置脚本
  Widget _buildPreScriptTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded,
                  size: 16, color: Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '在执行该目录下的任何 API 请求之前优先运行。可在此获取 Token、生成签名或注入公共请求头。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildSnippetChip(
                label: '+ 注入公共 Header',
                onTap: () => _insertScriptSnippet(
                  _preScriptController,
                  'pm.request.headers.add({ key: "X-Folder-Token", value: "folder_secret" });',
                ),
              ),
              _buildSnippetChip(
                label: '+ 生成时间戳签名',
                onTap: () => _insertScriptSnippet(
                  _preScriptController,
                  'const ts = Date.now();\nconst sign = CryptoJS.MD5(ts + "secret").toString();\npm.request.headers.add({ key: "X-Sign", value: sign });',
                ),
              ),
              _buildSnippetChip(
                label: '+ 设置环境变量',
                onTap: () => _insertScriptSnippet(
                  _preScriptController,
                  'pm.environment.set("requestTimestamp", Date.now());',
                ),
              ),
              _buildSnippetChip(
                label: '+ 打印调试日志',
                onTap: () => _insertScriptSnippet(
                  _preScriptController,
                  'console.log("正在执行目录【${widget.container.name}】前置公共脚本");',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TextFormField(
              controller: _preScriptController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12.5,
                height: 1.5,
                color: Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText:
                    '// 在此编写目录级公共前置脚本\n// 示例：\n// pm.request.headers.add({ key: "X-Trace-Dir", value: "${widget.container.name}" });',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide:
                      const BorderSide(color: Color(0xFF2563EB), width: 1.2),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
              onChanged: (_) {
                setState(() {});
                _syncToModel();
              },
            ),
          ),
        ],
      ),
    );
  }

  // Tab 4: 公共后置断言脚本
  Widget _buildPostScriptTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined,
                  size: 16, color: Color(0xFF10B981)),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '在该目录下的任何 API 收到响应后统一运行。可编写通用 HTTP 状态码断言、耗时检查或提取公共 Token。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildSnippetChip(
                label: '+ 断言状态码 200',
                onTap: () => _insertScriptSnippet(
                  _postScriptController,
                  'pm.test("HTTP Status is 200", function () {\n  pm.response.to.have.status(200);\n});',
                ),
              ),
              _buildSnippetChip(
                label: '+ 断言响应耗时 < 1000ms',
                onTap: () => _insertScriptSnippet(
                  _postScriptController,
                  'pm.test("Response time < 1000ms", function () {\n  pm.expect(pm.response.responseTime).to.be.below(1000);\n});',
                ),
              ),
              _buildSnippetChip(
                label: '+ 提取 Token 到环境变量',
                onTap: () => _insertScriptSnippet(
                  _postScriptController,
                  'const data = pm.response.json();\nif (data && data.token) {\n  pm.environment.set("apiKey", data.token);\n}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TextFormField(
              controller: _postScriptController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12.5,
                height: 1.5,
                color: Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText:
                    '// 在此编写目录级公共后置断言脚本\n// pm.test("Status code is 200", function () {\n//   pm.response.to.have.status(200);\n// });',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide:
                      const BorderSide(color: Color(0xFF2563EB), width: 1.2),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
              onChanged: (_) {
                setState(() {});
                _syncToModel();
              },
            ),
          ),
        ],
      ),
    );
  }

  // Tab 5: 目录基础信息
  Widget _buildInfoTab() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '目录名称',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nameController,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: '输入目录名称',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            ),
            onChanged: (_) {
              setState(() {});
              _syncToModel();
            },
          ),
          const SizedBox(height: 18),
          const Text(
            '目录描述与备注说明',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _descController,
            maxLines: 5,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: '输入该目录模块的业务场景、负责人或公共鉴权说明...',
              contentPadding: EdgeInsets.all(12),
            ),
            onChanged: (_) => _syncToModel(),
          ),
        ],
      ),
    );
  }

  Widget _buildSnippetChip({
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Color(0xFF334155),
          ),
        ),
      ),
    );
  }
}
