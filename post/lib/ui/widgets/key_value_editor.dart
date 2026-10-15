import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/api_request.dart';

class KeyValueEditor extends StatelessWidget {
  final List<KeyValueItem> items;
  final VoidCallback onChanged;
  final String keyPlaceholder;
  final String valuePlaceholder;
  final String descriptionPlaceholder;
  final bool isFormData;

  const KeyValueEditor({
    super.key,
    required this.items,
    required this.onChanged,
    this.keyPlaceholder = '输入参数名',
    this.valuePlaceholder = '输入参数值',
    this.descriptionPlaceholder = '输入参数说明',
    this.isFormData = false,
  });

  Future<void> _pickFile(KeyValueItem item) async {
    final file = await FilePicker.pickFile(
      dialogTitle: '选择要上传的文件',
    );
    if (file != null && file.path != null) {
      item.value = file.path!;
      onChanged();
    }
  }

  static const BorderSide _gridBorder = BorderSide(color: Color(0xFFE2E8F0), width: 1);

  @override
  Widget build(BuildContext context) {
    final allEnabled = items.isNotEmpty && items.every((e) => e.isEnabled);

    return Container(
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
          // 1. 表格表头行
          Container(
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              border: Border(bottom: _gridBorder),
            ),
            child: Row(
              children: [
                // 全选勾选列
                Container(
                  width: 38,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    border: Border(right: _gridBorder),
                  ),
                  child: items.isEmpty
                      ? const Icon(Icons.check_box_outline_blank_rounded,
                          size: 15, color: Color(0xFFCBD5E1))
                      : Transform.scale(
                          scale: 0.82,
                          child: Checkbox(
                            value: allEnabled,
                            activeColor: const Color(0xFF2563EB),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(3.5)),
                            onChanged: (val) {
                              final target = val ?? false;
                              for (final item in items) {
                                item.isEnabled = target;
                              }
                              onChanged();
                            },
                          ),
                        ),
                ),

                // 参数名列
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    decoration: const BoxDecoration(
                      border: Border(right: _gridBorder),
                    ),
                    child: const Text(
                      '参数名',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                ),

                // Form-Data 类型列
                if (isFormData)
                  Container(
                    width: 96,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.centerLeft,
                    decoration: const BoxDecoration(
                      border: Border(right: _gridBorder),
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

                // 参数值列
                Expanded(
                  flex: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    decoration: const BoxDecoration(
                      border: Border(right: _gridBorder),
                    ),
                    child: const Text(
                      '参数值',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                ),

                // 说明列
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    decoration: const BoxDecoration(
                      border: Border(right: _gridBorder),
                    ),
                    child: const Text(
                      '参数说明',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                ),

                // 操作列
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

          // 2. 表格数据行列表
          if (items.isEmpty)
            Container(
              height: 44,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: _gridBorder),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.table_rows_outlined,
                      size: 15, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 6),
                  Text(
                    '暂无${isFormData ? "表单字段" : "参数"}，点击下方「+ 添加一行」直接在表格中录入',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final rowTextColor = item.isEnabled
                    ? const Color(0xFF0F172A)
                    : const Color(0xFF94A3B8);

                return Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: item.isEnabled
                        ? Colors.white
                        : const Color(0xFFF8FAFC),
                    border: const Border(bottom: _gridBorder),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 启用复选框单元格
                      Container(
                        width: 38,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          border: Border(right: _gridBorder),
                        ),
                        child: Transform.scale(
                          scale: 0.82,
                          child: Checkbox(
                            value: item.isEnabled,
                            activeColor: const Color(0xFF2563EB),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(3.5)),
                            onChanged: (val) {
                              item.isEnabled = val ?? true;
                              onChanged();
                            },
                          ),
                        ),
                      ),

                      // Key 单元格
                      Expanded(
                        flex: 3,
                        child: Container(
                          decoration: const BoxDecoration(
                            border: Border(right: _gridBorder),
                          ),
                          alignment: Alignment.centerLeft,
                          child: TextFormField(
                            key: ValueKey('key_${item.hashCode}_$index'),
                            initialValue: item.key,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontFamily: 'Consolas',
                              color: rowTextColor,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: keyPlaceholder,
                              hintStyle: const TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 12,
                                fontWeight: FontWeight.normal,
                              ),
                              filled: false,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                            onChanged: (val) {
                              item.key = val;
                              onChanged();
                            },
                          ),
                        ),
                      ),

                      // Form-Data 类型下拉单元格
                      if (isFormData)
                        Container(
                          width: 96,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: const BoxDecoration(
                            border: Border(right: _gridBorder),
                          ),
                          alignment: Alignment.centerLeft,
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: item.type == 'file' ? 'file' : 'text',
                              isExpanded: true,
                              isDense: true,
                              style: TextStyle(
                                fontSize: 12,
                                color: rowTextColor,
                                fontWeight: FontWeight.w600,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'text',
                                  child: Text('Text'),
                                ),
                                DropdownMenuItem(
                                  value: 'file',
                                  child: Text('File'),
                                ),
                              ],
                              onChanged: (val) {
                                item.type = val ?? 'text';
                                onChanged();
                              },
                            ),
                          ),
                        ),

                      // Value 单元格 (支持 Text 或 File 选择)
                      Expanded(
                        flex: 4,
                        child: Container(
                          decoration: const BoxDecoration(
                            border: Border(right: _gridBorder),
                          ),
                          alignment: Alignment.centerLeft,
                          child: item.type == 'file'
                              ? Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        key: ValueKey(
                                            'val_file_${item.hashCode}_$index'),
                                        initialValue: item.value,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'Consolas',
                                          color: rowTextColor,
                                        ),
                                        decoration: const InputDecoration(
                                          hintText: '选择或输入文件路径...',
                                          hintStyle: TextStyle(
                                            color: Color(0xFFCBD5E1),
                                            fontSize: 11.5,
                                          ),
                                          filled: false,
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 8),
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                        ),
                                        onChanged: (val) {
                                          item.value = val;
                                          onChanged();
                                        },
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () => _pickFile(item),
                                      child: Container(
                                        margin: const EdgeInsets.only(right: 6),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEFF6FF),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: const Color(0xFFBFDBFE)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.folder_open_rounded,
                                                size: 13,
                                                color: Color(0xFF2563EB)),
                                            SizedBox(width: 3),
                                            Text(
                                              '选择文件',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF2563EB),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : TextFormField(
                                  key: ValueKey('val_${item.hashCode}_$index'),
                                  initialValue: item.value,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontFamily: 'Consolas',
                                    color: rowTextColor,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: valuePlaceholder,
                                    hintStyle: const TextStyle(
                                      color: Color(0xFFCBD5E1),
                                      fontSize: 12,
                                    ),
                                    filled: false,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                  ),
                                  onChanged: (val) {
                                    item.value = val;
                                    onChanged();
                                  },
                                ),
                        ),
                      ),

                      // Description 单元格
                      Expanded(
                        flex: 3,
                        child: Container(
                          decoration: const BoxDecoration(
                            border: Border(right: _gridBorder),
                          ),
                          alignment: Alignment.centerLeft,
                          child: TextFormField(
                            key: ValueKey('desc_${item.hashCode}_$index'),
                            initialValue: item.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: item.isEnabled
                                  ? const Color(0xFF475569)
                                  : const Color(0xFF94A3B8),
                            ),
                            decoration: InputDecoration(
                              hintText: descriptionPlaceholder,
                              hintStyle: const TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 11.5,
                              ),
                              filled: false,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                            onChanged: (val) {
                              item.description = val;
                              onChanged();
                            },
                          ),
                        ),
                      ),

                      // 删除操作单元格
                      SizedBox(
                        width: 40,
                        child: Center(
                          child: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 16),
                            color: const Color(0xFF94A3B8),
                            hoverColor: const Color(0xFFFEE2E2),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                            tooltip: '删除此行',
                            onPressed: () {
                              items.removeAt(index);
                              onChanged();
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

          // 3. 表格底部快捷新增栏 (Table Footer Action Row)
          Material(
            color: const Color(0xFFF8FAFC),
            child: InkWell(
              onTap: () {
                items.add(KeyValueItem(key: '', value: ''));
                onChanged();
              },
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.add_rounded,
                        size: 15, color: Color(0xFF2563EB)),
                    const SizedBox(width: 4),
                    Text(
                      isFormData ? '添加一行表单参数' : '添加一行参数',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '共 ${items.length} 项，已启用 ${items.where((e) => e.isEnabled && e.key.trim().isNotEmpty).length} 项',
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
    );
  }
}
