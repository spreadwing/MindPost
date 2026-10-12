import 'package:flutter/material.dart';
import '../../models/api_request.dart';

class KeyValueEditor extends StatelessWidget {
  final List<KeyValueItem> items;
  final VoidCallback onChanged;
  final String keyPlaceholder;
  final String valuePlaceholder;

  const KeyValueEditor({
    super.key,
    required this.items,
    required this.onChanged,
    this.keyPlaceholder = 'Key',
    this.valuePlaceholder = 'Value',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Text(
              '暂无数据，点击下方添加一行',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Checkbox(
                      value: item.isEnabled,
                      activeColor: const Color(0xFF3B82F6),
                      onChanged: (val) {
                        item.isEnabled = val ?? true;
                        onChanged();
                      },
                    ),
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        initialValue: item.key,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: keyPlaceholder,
                          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        onChanged: (val) {
                          item.key = val;
                          onChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 6,
                      child: TextFormField(
                        initialValue: item.value,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: valuePlaceholder,
                          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        onChanged: (val) {
                          item.value = val;
                          onChanged();
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: Colors.red.shade400,
                      onPressed: () {
                        items.removeAt(index);
                        onChanged();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            items.add(KeyValueItem(key: '', value: ''));
            onChanged();
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('添加参数项', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            foregroundColor: const Color(0xFF3B82F6),
          ),
        ),
      ],
    );
  }
}
