import 'package:flutter/material.dart';
import '../app_fonts.dart';
import '../../models/api_request.dart';
import 'key_value_editor.dart';
import 'json_syntax_highlighter.dart';

class ContainerSettingsDialog extends StatefulWidget {
  final dynamic container; // ApiCollection 或 ApiFolder
  final bool isCollection;
  final VoidCallback onSaved;

  const ContainerSettingsDialog({
    super.key,
    required this.container,
    this.isCollection = true,
    required this.onSaved,
  });

  @override
  State<ContainerSettingsDialog> createState() =>
      _ContainerSettingsDialogState();
}

class _ContainerSettingsDialogState extends State<ContainerSettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late JsSyntaxHighlightController _preScriptController;
  late JsSyntaxHighlightController _postScriptController;

  late List<KeyValueItem> _headers;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _nameController = TextEditingController(text: widget.container.name);
    _descController = TextEditingController(text: widget.container.description);
    _preScriptController =
        JsSyntaxHighlightController(text: widget.container.preRequestScript);
    _postScriptController =
        JsSyntaxHighlightController(text: widget.container.postRequestScript);

    _headers = widget.container.headers as List<KeyValueItem>;
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

  void _save() {
    widget.container.name = _nameController.text.trim().isEmpty
        ? '未命名目录'
        : _nameController.text.trim();
    widget.container.description = _descController.text.trim();
    widget.container.preRequestScript = _preScriptController.text;
    widget.container.postRequestScript = _postScriptController.text;

    widget.onSaved();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    const titleType = '目录';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        width: 820,
        height: 580,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.folder_outlined,
                  color: Color(0xFF3B82F6),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  '$titleType级公共配置管理 - ${widget.container.name}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 16),
            Container(
              height: 38,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF3B82F6),
                unselectedLabelColor: Colors.grey.shade600,
                labelStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                tabs: [
                  const Tab(text: '基础信息'),
                  Tab(text: '公共 Headers · ${_headers.length}'),
                  const Tab(text: '公共前置脚本'),
                  const Tab(text: '公共后置断言'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: 基础信息
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: '$titleType名称',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _descController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: '$titleType描述与说明',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: const Color(0xFF3B82F6)
                                    .withValues(alpha: 0.2)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: Color(0xFF3B82F6), size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '级联继承提示：在当前$titleType配置的公共 Headers、前置脚本和后置断言，将对本$titleType下所有下级目录和 API 自动生效并自顶向下递归继承。',
                                  style: TextStyle(
                                      fontSize: 12, color: Color(0xFF1E40AF)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tab 2: 公共 Headers
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: SingleChildScrollView(
                      child: KeyValueEditor(
                        items: _headers,
                        onChanged: () => setState(() {}),
                        keyPlaceholder: 'Header Name (如 X-Auth-Token)',
                        valuePlaceholder: 'Header Value (支持 {{apiKey}})',
                      ),
                    ),
                  ),

                  // Tab 3: 公共前置脚本
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '在此配置当前$titleType下所有请求发送前执行的公共 JavaScript 脚本',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                            const Spacer(),
                            ActionChip(
                              label: const Text('插入公共 Token 校验',
                                  style: TextStyle(fontSize: 10)),
                              onPressed: () {
                                _preScriptController.text += '''\n
// 公共层级前置脚本：自动附带时间戳或公共签名
pm.request.headers.add({ key: "X-Collection-Ts", value: Date.now() });
console.log("执行【${widget.container.name}】公共前置处理");
''';
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _preScriptController,
                            maxLines: null,
                            expands: true,
                            style: const TextStyle(
                                fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback, fontSize: 12),
                            decoration: const InputDecoration(
                              hintText:
                                  '// 编写公共前置脚本...\npm.request.headers.add({ ... });',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tab 4: 公共后置断言
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '在此配置当前$titleType下所有请求返回后执行的公共测试与断言',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                            const Spacer(),
                            ActionChip(
                              label: const Text('插入响应耗时断言',
                                  style: TextStyle(fontSize: 10)),
                              onPressed: () {
                                _postScriptController.text += '''\n
pm.test("响应耗时必须小于 2000ms", function () {
    if (pm.response.responseTime > 2000) {
        throw new Error("请求超时，实际耗时: " + pm.response.responseTime + "ms");
    }
});
''';
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _postScriptController,
                            maxLines: null,
                            expands: true,
                            style: const TextStyle(
                                fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback, fontSize: 12),
                            decoration: const InputDecoration(
                              hintText:
                                  '// 编写公共测试脚本...\npm.test("公共断言", function() { ... });',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
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
                  onPressed: _save,
                  child: const Text('保存配置'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
