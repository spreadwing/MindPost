import 'dart:convert';
import '../app_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 具有 JSON 语法实时高亮能力的 TextEditingController
class JsonSyntaxHighlightController extends TextEditingController {
  JsonSyntaxHighlightController({super.text});

  // 语法高亮色彩定义
  static const Color keyColor = Color(0xFF1D4ED8); // 键名：深蓝色
  static const Color stringColor = Color(0xFF047857); // 字符串：翡翠绿
  static const Color numberColor = Color(0xFFD97706); // 数值：琥珀橙
  static const Color boolNullColor = Color(0xFF7C3AED); // 布尔/Null：紫罗兰
  static const Color punctuationColor = Color(0xFF475569); // 括号与逗号：石板灰
  static const Color defaultColor = Color(0xFF1E293B); // 默认文本

  // JSON 语法标记匹配正则
  static final RegExp _jsonRegex = RegExp(
    r'(?<key>"(\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*"\s*(?=:))' // Key: "xxx":
    r'|(?<string>"(\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*")' // String: "xxx"
    r'|(?<boolNull>\b(true|false|null)\b)' // Boolean/Null
    r'|(?<number>-?\b\d+(\.\d+)?([eE][+-]?\d+)?\b)' // Number
    r'|(?<punct>[{}[\],:])', // 标点
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ??
        const TextStyle(
          fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
          fontSize: 13,
          color: defaultColor,
          height: 1.45,
        );

    final rawText = value.text;
    if (rawText.isEmpty) {
      return TextSpan(style: baseStyle, text: rawText);
    }

    final spans = <InlineSpan>[];
    int lastMatchEnd = 0;

    for (final match in _jsonRegex.allMatches(rawText)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: rawText.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }

      if (match.namedGroup('key') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: baseStyle.copyWith(
            color: keyColor,
            fontWeight: FontWeight.w600,
          ),
        ));
      } else if (match.namedGroup('string') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: baseStyle.copyWith(color: stringColor),
        ));
      } else if (match.namedGroup('boolNull') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: baseStyle.copyWith(
            color: boolNullColor,
            fontWeight: FontWeight.bold,
          ),
        ));
      } else if (match.namedGroup('number') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: baseStyle.copyWith(color: numberColor),
        ));
      } else if (match.namedGroup('punct') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: baseStyle.copyWith(
            color: punctuationColor,
            fontWeight: FontWeight.w600,
          ),
        ));
      } else {
        spans.add(TextSpan(
          text: match.group(0),
          style: baseStyle,
        ));
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < rawText.length) {
      spans.add(TextSpan(
        text: rawText.substring(lastMatchEnd),
        style: baseStyle,
      ));
    }

    return TextSpan(style: baseStyle, children: spans);
  }
}

/// 具有 JavaScript 脚本语法实时高亮能力的 TextEditingController
class JsSyntaxHighlightController extends TextEditingController {
  JsSyntaxHighlightController({super.text});

  // JavaScript 语法高亮配色定义
  static const Color commentColor = Color(0xFF64748B); // 注释：石板灰斜体
  static const Color stringColor = Color(0xFF047857); // 字符串/模板字符串：翡翠绿
  static const Color keywordColor = Color(0xFF7C3AED); // 关键字：紫罗兰
  static const Color literalColor = Color(0xFFDB2777); // 布尔/null/undefined：玫红
  static const Color builtinColor = Color(0xFF0284C7); // 内置对象 (pm/CryptoJS/console等)：天蓝
  static const Color sdkPropColor = Color(0xFF1D4ED8); // SDK 属性与断言链：深蓝
  static const Color functionColor = Color(0xFF2563EB); // 函数/方法调用：皇家蓝
  static const Color objKeyColor = Color(0xFF0369A1); // 对象字面量键名：深青蓝
  static const Color numberColor = Color(0xFFD97706); // 数值：琥珀橙
  static const Color punctuationColor = Color(0xFF475569); // 运算符与括号：深灰
  static const Color defaultColor = Color(0xFF0F172A); // 默认标识符文本

  static final RegExp _jsRegex = RegExp(
    r'(?<comment>//[^\n]*|/\*[\s\S]*?\*/)'
    r'|(?<string>"(?:\\.|[^"\\])*"|'
    r"'(?:\\.|[^'\\])*'|"
    r'`(?:\\.|[^`\\])*`)'
    r'|(?<keyword>\b(?:const|let|var|function|return|if|else|for|while|do|switch|case|break|continue|try|catch|finally|throw|new|typeof|instanceof|in|of|async|await|class|extends|super|import|export|default|delete|void|yield|this)\b)'
    r'|(?<literal>\b(?:true|false|null|undefined|NaN|Infinity)\b)'
    r'|(?<builtin>\b(?:pm|apt|postman|CryptoJS|console|JSON|Date|Math|Object|Array|String|Number|Boolean|RegExp|Promise|Error|encodeURIComponent|decodeURIComponent|btoa|atob|parseInt|parseFloat|setTimeout|clearTimeout)\b)'
    r'|(?<sdkProp>(?<=\.)\b(?:environment|variables|globals|collectionVariables|request|response|headers|cookies|url|body|method|test|expect|to|be|have|not|status|ok|equal|eql|above|below|include|a|an|property|lengthOf|json|text|code|responseTime|get|set|unset|clear|add|remove|upsert|MD5|SHA1|SHA256|SHA512|HmacMD5|HmacSHA1|HmacSHA256|HmacSHA512|AES|DES|TripleDES|enc|Base64|Utf8|Hex|toString|now|log|warn|error|info| parse|stringify)\b)'
    r'|(?<funcCall>\b[a-zA-Z_$][a-zA-Z0-9_$]*(?=\s*\())'
    r'|(?<objKey>\b[a-zA-Z_$][a-zA-Z0-9_$]*(?=\s*:))'
    r'|(?<number>\b0[xX][0-9a-fA-F]+\b|-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b)'
    r'|(?<punct>[{}()[\].,:;+\-*/%=<>!&|?~^]+)',
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ??
        const TextStyle(
          fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
          fontSize: 12.5,
          color: defaultColor,
          height: 1.45,
        );

    final rawText = value.text;
    if (rawText.isEmpty) {
      return TextSpan(style: baseStyle, text: rawText);
    }

    final spans = <InlineSpan>[];
    int lastMatchEnd = 0;

    for (final match in _jsRegex.allMatches(rawText)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: rawText.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }

      if (match.namedGroup('comment') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: baseStyle.copyWith(
            color: commentColor,
            fontStyle: FontStyle.italic,
          ),
        ));
      } else if (match.namedGroup('string') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: baseStyle.copyWith(color: stringColor),
        ));
      } else if (match.namedGroup('keyword') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: baseStyle.copyWith(
            color: keywordColor,
            fontWeight: FontWeight.w700,
          ),
        ));
      } else if (match.namedGroup('literal') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: baseStyle.copyWith(
            color: literalColor,
            fontWeight: FontWeight.w700,
          ),
        ));
      } else if (match.namedGroup('builtin') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: baseStyle.copyWith(
            color: builtinColor,
            fontWeight: FontWeight.w700,
          ),
        ));
      } else if (match.namedGroup('sdkProp') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: baseStyle.copyWith(
            color: sdkPropColor,
            fontWeight: FontWeight.w600,
          ),
        ));
      } else if (match.namedGroup('funcCall') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: baseStyle.copyWith(
            color: functionColor,
            fontWeight: FontWeight.w600,
          ),
        ));
      } else if (match.namedGroup('objKey') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: baseStyle.copyWith(
            color: objKeyColor,
            fontWeight: FontWeight.w600,
          ),
        ));
      } else if (match.namedGroup('number') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: baseStyle.copyWith(color: numberColor),
        ));
      } else if (match.namedGroup('punct') != null) {
        spans.add(TextSpan(
          text: match.group(0),
          style: baseStyle.copyWith(color: punctuationColor),
        ));
      } else {
        spans.add(TextSpan(
          text: match.group(0),
          style: baseStyle,
        ));
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < rawText.length) {
      spans.add(TextSpan(
        text: rawText.substring(lastMatchEnd),
        style: baseStyle,
      ));
    }

    return TextSpan(style: baseStyle, children: spans);
  }
}

/// 用于渲染只读高亮响应/内容的视图组件，支持 JSON 对象与列表折叠收起、Ctrl+F 关键字查找定位、右击 Array Key 切换表格查看
class JsonHighlightedViewer extends StatefulWidget {
  final String jsonText;
  final TextStyle? style;
  final String searchQuery;
  final int activeMatchIndex;
  final ValueChanged<int>? onMatchCountChanged;
  final void Function(String path, String? keyName, List<dynamic> arrayData)?
      onViewArrayAsTable;

  const JsonHighlightedViewer({
    super.key,
    required this.jsonText,
    this.style,
    this.searchQuery = '',
    this.activeMatchIndex = 0,
    this.onMatchCountChanged,
    this.onViewArrayAsTable,
  });

  @override
  State<JsonHighlightedViewer> createState() => _JsonHighlightedViewerState();
}

class _JsonHighlightedViewerState extends State<JsonHighlightedViewer> {
  final Set<String> _collapsedPaths = {};
  dynamic _decodedJson;
  bool _isValidComplexJson = false;
  int _lastReportedMatchCount = -1;
  String _lastScrolledSignature = '';
  GlobalKey _activeMatchKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _parseJson();
  }

  @override
  void didUpdateWidget(covariant JsonHighlightedViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jsonText != widget.jsonText) {
      _collapsedPaths.clear();
      _lastReportedMatchCount = -1;
      _lastScrolledSignature = '';
      _parseJson();
    }
  }

  void _parseJson() {
    try {
      final decoded = json.decode(widget.jsonText);
      if (decoded is Map || decoded is List) {
        _decodedJson = decoded;
        _isValidComplexJson = true;
        return;
      }
    } catch (_) {}
    _decodedJson = null;
    _isValidComplexJson = false;
  }

  void _togglePath(String path) {
    setState(() {
      if (_collapsedPaths.contains(path)) {
        _collapsedPaths.remove(path);
      } else {
        _collapsedPaths.add(path);
      }
    });
  }

  void _collectCollapsiblePaths(dynamic node, String path, List<String> out) {
    if (node is Map && node.isNotEmpty) {
      if (path != r'$') {
        out.add(path);
      }
      for (final entry in node.entries) {
        _collectCollapsiblePaths(entry.value, '$path.${entry.key}', out);
      }
    } else if (node is List && node.isNotEmpty) {
      if (path != r'$') {
        out.add(path);
      }
      for (int i = 0; i < node.length; i++) {
        _collectCollapsiblePaths(node[i], '$path[$i]', out);
      }
    }
  }

  void _collapseAllSubNodes() {
    if (!_isValidComplexJson) return;
    final paths = <String>[];
    _collectCollapsiblePaths(_decodedJson, r'$', paths);
    setState(() {
      _collapsedPaths
        ..clear()
        ..addAll(paths);
    });
  }

  void _expandAllNodes() {
    setState(() {
      _collapsedPaths.clear();
    });
  }

  bool _nodeContainsQuery(dynamic node, String? keyName, String queryLower) {
    if (queryLower.isEmpty) return false;
    if (keyName != null && keyName.toLowerCase().contains(queryLower)) {
      return true;
    }
    if (node is Map) {
      for (final entry in node.entries) {
        if (_nodeContainsQuery(
            entry.value, entry.key.toString(), queryLower)) {
          return true;
        }
      }
      return false;
    } else if (node is List) {
      for (final item in node) {
        if (_nodeContainsQuery(item, null, queryLower)) {
          return true;
        }
      }
      return false;
    } else {
      final text = node is String ? json.encode(node) : node.toString();
      return text.toLowerCase().contains(queryLower);
    }
  }

  Future<void> _showArrayContextMenu(
    Offset position,
    String path,
    String? keyName,
    List<dynamic> arrayData,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final displayKey =
        keyName ?? (path.startsWith(r'$.') ? path.substring(2) : path);

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'view_table',
          height: 36,
          child: Row(
            children: [
              const Icon(Icons.table_chart_outlined,
                  size: 16, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              Text('切换成表格形式查看 · $displayKey',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        const PopupMenuItem<String>(
          value: 'copy_array',
          height: 34,
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 15, color: Color(0xFF475569)),
              SizedBox(width: 8),
              Text('复制数组 JSON', style: TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
        if (keyName != null)
          const PopupMenuItem<String>(
            value: 'copy_key',
            height: 34,
            child: Row(
              children: [
                Icon(Icons.label_outline_rounded,
                    size: 15, color: Color(0xFF475569)),
                SizedBox(width: 8),
                Text('复制字段名', style: TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
      ],
    );

    if (!mounted || action == null) return;
    if (action == 'view_table') {
      widget.onViewArrayAsTable?.call(path, keyName, arrayData);
    } else if (action == 'copy_array') {
      final formatted = const JsonEncoder.withIndent('  ').convert(arrayData);
      await Clipboard.setData(ClipboardData(text: formatted));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已复制数组 $displayKey 内容'),
            duration: const Duration(milliseconds: 1200),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else if (action == 'copy_key' && keyName != null) {
      await Clipboard.setData(ClipboardData(text: keyName));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已复制字段名 $keyName'),
            duration: const Duration(milliseconds: 1200),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  List<InlineSpan> _buildHighlightedSpans({
    required String text,
    required TextStyle style,
    required String queryLower,
    required int Function() nextMatchIndex,
  }) {
    if (queryLower.isEmpty || text.isEmpty) {
      return [TextSpan(text: text, style: style)];
    }

    final lowerText = text.toLowerCase();
    int start = 0;
    int indexOfMatch = lowerText.indexOf(queryLower, start);
    if (indexOfMatch < 0) {
      return [TextSpan(text: text, style: style)];
    }

    final spans = <InlineSpan>[];
    while (indexOfMatch >= 0) {
      if (indexOfMatch > start) {
        spans.add(TextSpan(
          text: text.substring(start, indexOfMatch),
          style: style,
        ));
      }

      final matchText =
          text.substring(indexOfMatch, indexOfMatch + queryLower.length);
      final matchIdx = nextMatchIndex();
      final isActive = matchIdx == widget.activeMatchIndex;

      if (isActive) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              key: _activeMatchKey,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                matchText,
                style: style.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: matchText,
            style: style.copyWith(
              backgroundColor: const Color(0xFFFEF08A),
              color: const Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }

      start = indexOfMatch + queryLower.length;
      indexOfMatch = lowerText.indexOf(queryLower, start);
    }

    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: style,
      ));
    }

    return spans;
  }

  void _notifyAndScrollIfNeeded(int matchCount, String queryLower) {
    if (_lastReportedMatchCount != matchCount) {
      _lastReportedMatchCount = matchCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onMatchCountChanged?.call(matchCount);
        }
      });
    }

    final sig = '$queryLower#${widget.activeMatchIndex}#$matchCount';
    if (queryLower.isNotEmpty &&
        matchCount > 0 &&
        _lastScrolledSignature != sig) {
      _lastScrolledSignature = sig;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _activeMatchKey.currentContext;
        if (ctx != null && mounted) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.35,
            duration: const Duration(milliseconds: 160),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = widget.style ??
        const TextStyle(
          fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
          fontSize: 13,
          color: JsonSyntaxHighlightController.defaultColor,
          height: 1.45,
        );

    final queryLower = widget.searchQuery.trim().toLowerCase();
    int matchCounter = 0;
    _activeMatchKey = GlobalKey();

    if (!_isValidComplexJson) {
      if (queryLower.isEmpty) {
        _notifyAndScrollIfNeeded(0, queryLower);
        final controller =
            JsonSyntaxHighlightController(text: widget.jsonText);
        final textSpan = controller.buildTextSpan(
          context: context,
          style: baseStyle,
          withComposing: false,
        );
        return SelectableText.rich(textSpan, style: baseStyle);
      } else {
        final spans = _buildHighlightedSpans(
          text: widget.jsonText,
          style: baseStyle,
          queryLower: queryLower,
          nextMatchIndex: () => matchCounter++,
        );
        _notifyAndScrollIfNeeded(matchCounter, queryLower);
        return SelectableText.rich(
          TextSpan(style: baseStyle, children: spans),
          style: baseStyle,
        );
      }
    }

    final lines = <Widget>[];
    _buildJsonLines(
      node: _decodedJson,
      keyName: null,
      path: r'$',
      depth: 0,
      isLast: true,
      baseStyle: baseStyle,
      queryLower: queryLower,
      nextMatchIndex: () => matchCounter++,
      outLines: lines,
    );

    _notifyAndScrollIfNeeded(matchCounter, queryLower);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部快捷展开/收起工具条
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              InkWell(
                onTap: _expandAllNodes,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.unfold_more_rounded,
                          size: 13, color: Color(0xFF475569)),
                      SizedBox(width: 3),
                      Text(
                        '全部展开',
                        style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF475569),
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: _collapseAllSubNodes,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.unfold_less_rounded,
                          size: 13, color: Color(0xFF475569)),
                      SizedBox(width: 3),
                      Text(
                        '全部收起',
                        style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF475569),
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines,
          ),
        ),
      ],
    );
  }

  void _buildJsonLines({
    required dynamic node,
    required String? keyName,
    required String path,
    required int depth,
    required bool isLast,
    required TextStyle baseStyle,
    required String queryLower,
    required int Function() nextMatchIndex,
    required List<Widget> outLines,
  }) {
    final keyStyle = baseStyle.copyWith(
      color: JsonSyntaxHighlightController.keyColor,
      fontWeight: FontWeight.w600,
    );
    final punctStyle = baseStyle.copyWith(
      color: JsonSyntaxHighlightController.punctuationColor,
      fontWeight: FontWeight.w600,
    );
    final commaSpan = isLast ? null : TextSpan(text: ',', style: punctStyle);

    List<InlineSpan> buildKeyPrefix() {
      if (keyName == null) return [];
      return [
        ..._buildHighlightedSpans(
          text: json.encode(keyName),
          style: keyStyle,
          queryLower: queryLower,
          nextMatchIndex: nextMatchIndex,
        ),
        TextSpan(text: ': ', style: punctStyle),
      ];
    }

    if (node is Map) {
      if (node.isEmpty) {
        outLines.add(_buildLineRow(
          depth: depth,
          collapsible: false,
          isCollapsed: false,
          onToggle: null,
          spans: [
            ...buildKeyPrefix(),
            TextSpan(text: '{}', style: punctStyle),
            ?commaSpan,
          ],
          baseStyle: baseStyle,
        ));
        return;
      }

      final isCollapsed = _collapsedPaths.contains(path) &&
          !(queryLower.isNotEmpty &&
              _nodeContainsQuery(node, null, queryLower));
      if (isCollapsed) {
        outLines.add(_buildLineRow(
          depth: depth,
          collapsible: true,
          isCollapsed: true,
          onToggle: () => _togglePath(path),
          spans: [
            ...buildKeyPrefix(),
            TextSpan(text: '{ ... }', style: punctStyle),
          ],
          collapsedCount: node.length,
          trailingComma: commaSpan,
          baseStyle: baseStyle,
        ));
        return;
      }

      // 展开状态：首行 {
      outLines.add(_buildLineRow(
        depth: depth,
        collapsible: true,
        isCollapsed: false,
        onToggle: () => _togglePath(path),
        spans: [
          ...buildKeyPrefix(),
          TextSpan(text: '{', style: punctStyle),
        ],
        baseStyle: baseStyle,
      ));

      final entries = node.entries.toList();
      for (int i = 0; i < entries.length; i++) {
        final entry = entries[i];
        _buildJsonLines(
          node: entry.value,
          keyName: entry.key.toString(),
          path: '$path.${entry.key}',
          depth: depth + 1,
          isLast: i == entries.length - 1,
          baseStyle: baseStyle,
          queryLower: queryLower,
          nextMatchIndex: nextMatchIndex,
          outLines: outLines,
        );
      }

      // 尾行 }
      outLines.add(_buildLineRow(
        depth: depth,
        collapsible: false,
        isCollapsed: false,
        onToggle: null,
        spans: [
          TextSpan(text: '}', style: punctStyle),
          ?commaSpan,
        ],
        baseStyle: baseStyle,
      ));
      return;
    }

    if (node is List) {
      void handleSecondaryTap(TapDownDetails details) {
        _showArrayContextMenu(details.globalPosition, path, keyName, node);
      }

      if (node.isEmpty) {
        outLines.add(_buildLineRow(
          depth: depth,
          collapsible: false,
          isCollapsed: false,
          onToggle: null,
          onSecondaryTapDown: handleSecondaryTap,
          onTableQuickTap: widget.onViewArrayAsTable != null
              ? () => widget.onViewArrayAsTable!(path, keyName, node)
              : null,
          spans: [
            ...buildKeyPrefix(),
            TextSpan(text: '[]', style: punctStyle),
            ?commaSpan,
          ],
          baseStyle: baseStyle,
        ));
        return;
      }

      final isCollapsed = _collapsedPaths.contains(path) &&
          !(queryLower.isNotEmpty &&
              _nodeContainsQuery(node, null, queryLower));
      if (isCollapsed) {
        outLines.add(_buildLineRow(
          depth: depth,
          collapsible: true,
          isCollapsed: true,
          onToggle: () => _togglePath(path),
          onSecondaryTapDown: handleSecondaryTap,
          onTableQuickTap: widget.onViewArrayAsTable != null
              ? () => widget.onViewArrayAsTable!(path, keyName, node)
              : null,
          spans: [
            ...buildKeyPrefix(),
            TextSpan(text: '[ ... ]', style: punctStyle),
          ],
          collapsedCount: node.length,
          trailingComma: commaSpan,
          baseStyle: baseStyle,
        ));
        return;
      }

      // 展开状态：首行 [
      outLines.add(_buildLineRow(
        depth: depth,
        collapsible: true,
        isCollapsed: false,
        onToggle: () => _togglePath(path),
        onSecondaryTapDown: handleSecondaryTap,
        onTableQuickTap: widget.onViewArrayAsTable != null
            ? () => widget.onViewArrayAsTable!(path, keyName, node)
            : null,
        spans: [
          ...buildKeyPrefix(),
          TextSpan(text: '[', style: punctStyle),
        ],
        collapsedCount: node.length,
        baseStyle: baseStyle,
      ));

      for (int i = 0; i < node.length; i++) {
        _buildJsonLines(
          node: node[i],
          keyName: null,
          path: '$path[$i]',
          depth: depth + 1,
          isLast: i == node.length - 1,
          baseStyle: baseStyle,
          queryLower: queryLower,
          nextMatchIndex: nextMatchIndex,
          outLines: outLines,
        );
      }

      // 尾行 ]
      outLines.add(_buildLineRow(
        depth: depth,
        collapsible: false,
        isCollapsed: false,
        onToggle: null,
        spans: [
          TextSpan(text: ']', style: punctStyle),
          ?commaSpan,
        ],
        baseStyle: baseStyle,
      ));
      return;
    }

    // 基本类型
    late String valueText;
    late TextStyle valueStyle;
    if (node is String) {
      valueText = json.encode(node);
      valueStyle = baseStyle.copyWith(
          color: JsonSyntaxHighlightController.stringColor);
    } else if (node is num) {
      valueText = node.toString();
      valueStyle = baseStyle.copyWith(
          color: JsonSyntaxHighlightController.numberColor);
    } else if (node is bool || node == null) {
      valueText = node.toString();
      valueStyle = baseStyle.copyWith(
        color: JsonSyntaxHighlightController.boolNullColor,
        fontWeight: FontWeight.bold,
      );
    } else {
      valueText = node.toString();
      valueStyle = baseStyle;
    }

    outLines.add(_buildLineRow(
      depth: depth,
      collapsible: false,
      isCollapsed: false,
      onToggle: null,
      spans: [
        ...buildKeyPrefix(),
        ..._buildHighlightedSpans(
          text: valueText,
          style: valueStyle,
          queryLower: queryLower,
          nextMatchIndex: nextMatchIndex,
        ),
        ?commaSpan,
      ],
      baseStyle: baseStyle,
    ));
  }

  Widget _buildLineRow({
    required int depth,
    required bool collapsible,
    required bool isCollapsed,
    required VoidCallback? onToggle,
    required List<InlineSpan> spans,
    required TextStyle baseStyle,
    GestureTapDownCallback? onSecondaryTapDown,
    VoidCallback? onTableQuickTap,
    int? collapsedCount,
    InlineSpan? trailingComma,
  }) {
    final rowContent = Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (collapsible)
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                width: 18,
                height: 19,
                child: Icon(
                  isCollapsed
                      ? Icons.keyboard_arrow_right_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: const Color(0xFF64748B),
                ),
              ),
            )
          else
            const SizedBox(width: 18, height: 19),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text.rich(
                  TextSpan(style: baseStyle, children: spans),
                ),
                if (isCollapsed && collapsedCount != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: onToggle,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 0.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Text(
                        '$collapsedCount 项',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF2563EB),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
                if (trailingComma != null)
                  Text.rich(
                    TextSpan(style: baseStyle, children: [trailingComma]),
                  ),
                if (onTableQuickTap != null) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: '右击或点击切换为表格形式查看',
                    child: InkWell(
                      onTap: onTableQuickTap,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 0.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.table_chart_outlined,
                                size: 11, color: Color(0xFF2563EB)),
                            SizedBox(width: 3),
                            Text(
                              '表格',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF2563EB),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onSecondaryTapDown != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: onSecondaryTapDown,
        child: rowContent,
      );
    }
    return rowContent;
  }
}

/// JSON 内部可转为表格展示的数组候选节点
class JsonArrayCandidate {
  final String path;
  final String label;
  final List<dynamic> items;

  JsonArrayCandidate({
    required this.path,
    required this.label,
    required this.items,
  });
}

/// 响应报文表格视图组件（支持任意 Array 节点展开为结构化表格，并支持 Ctrl+F 查找高亮）
class ResponseTableViewer extends StatefulWidget {
  final String jsonText;
  final String? selectedArrayPath;
  final String searchQuery;
  final int activeMatchIndex;
  final ValueChanged<int>? onMatchCountChanged;
  final ValueChanged<String>? onArrayPathChanged;
  final VoidCallback? onSwitchToJson;

  const ResponseTableViewer({
    super.key,
    required this.jsonText,
    this.selectedArrayPath,
    this.searchQuery = '',
    this.activeMatchIndex = 0,
    this.onMatchCountChanged,
    this.onArrayPathChanged,
    this.onSwitchToJson,
  });

  @override
  State<ResponseTableViewer> createState() => _ResponseTableViewerState();
}

class _ResponseTableViewerState extends State<ResponseTableViewer> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  int _lastReportedMatchCount = -1;
  String _lastScrolledSignature = '';
  GlobalKey _activeMatchKey = GlobalKey();

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  void _collectArrays(
    dynamic node,
    String path,
    List<JsonArrayCandidate> out,
  ) {
    if (node is List) {
      final cleanLabel =
          path == r'$' ? '根数组' : path.replaceFirst(r'$.', '');
      out.add(JsonArrayCandidate(
        path: path,
        label: '$cleanLabel · ${node.length} 条',
        items: node,
      ));
      for (int i = 0; i < node.length; i++) {
        if (node[i] is Map || node[i] is List) {
          _collectArrays(node[i], '$path[$i]', out);
        }
      }
    } else if (node is Map) {
      for (final entry in node.entries) {
        _collectArrays(entry.value, '$path.${entry.key}', out);
      }
    }
  }

  String _formatCellValue(dynamic val) {
    if (val == null) return 'null';
    if (val is Map || val is List) {
      return json.encode(val);
    }
    return val.toString();
  }

  Widget _buildCellText({
    required String text,
    required TextStyle style,
    required String queryLower,
    required int Function() nextMatchIndex,
  }) {
    if (queryLower.isEmpty || text.isEmpty) {
      return SelectableText(
        text,
        style: style,
        maxLines: 2,
      );
    }

    final lowerText = text.toLowerCase();
    int start = 0;
    int indexOfMatch = lowerText.indexOf(queryLower, start);
    if (indexOfMatch < 0) {
      return SelectableText(
        text,
        style: style,
        maxLines: 2,
      );
    }

    final spans = <InlineSpan>[];
    while (indexOfMatch >= 0) {
      if (indexOfMatch > start) {
        spans.add(TextSpan(
          text: text.substring(start, indexOfMatch),
          style: style,
        ));
      }

      final matchText =
          text.substring(indexOfMatch, indexOfMatch + queryLower.length);
      final matchIdx = nextMatchIndex();
      final isActive = matchIdx == widget.activeMatchIndex;

      if (isActive) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              key: _activeMatchKey,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                matchText,
                style: style.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: matchText,
            style: style.copyWith(
              backgroundColor: const Color(0xFFFEF08A),
              color: const Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }

      start = indexOfMatch + queryLower.length;
      indexOfMatch = lowerText.indexOf(queryLower, start);
    }

    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: style,
      ));
    }

    return SelectableText.rich(
      TextSpan(style: style, children: spans),
      maxLines: 2,
    );
  }

  void _notifyAndScrollIfNeeded(int matchCount, String queryLower) {
    if (_lastReportedMatchCount != matchCount) {
      _lastReportedMatchCount = matchCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onMatchCountChanged?.call(matchCount);
        }
      });
    }

    final sig = '$queryLower#${widget.activeMatchIndex}#$matchCount';
    if (queryLower.isNotEmpty &&
        matchCount > 0 &&
        _lastScrolledSignature != sig) {
      _lastScrolledSignature = sig;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _activeMatchKey.currentContext;
        if (ctx != null && mounted) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.35,
            duration: const Duration(milliseconds: 160),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    dynamic decoded;
    try {
      decoded = json.decode(widget.jsonText);
    } catch (_) {
      return const Center(
        child: Text(
          '当前响应不是合法 JSON，无法以表格形式展示',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
        ),
      );
    }

    final candidates = <JsonArrayCandidate>[];
    _collectArrays(decoded, r'$', candidates);

    final queryLower = widget.searchQuery.trim().toLowerCase();
    int matchCounter = 0;
    _activeMatchKey = GlobalKey();

    // 若 JSON 中没有任何数组，但根节点为 Map，则将其转为字段键值表展示
    if (candidates.isEmpty) {
      if (decoded is Map) {
        final entries = decoded.entries.toList();
        final rows = <Widget>[];
        for (int i = 0; i < entries.length; i++) {
          final e = entries[i];
          final kStr = e.key.toString();
          final vStr = _formatCellValue(e.value);
          rows.add(
            Container(
              decoration: BoxDecoration(
                color: i.isEven ? Colors.white : const Color(0xFFF8FAFC),
                border: const Border(
                  bottom: BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 52,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 7),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        border: Border(
                            right: BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                            fontSize: 11.5, color: Color(0xFF94A3B8)),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: const BoxDecoration(
                          border: Border(
                              right: BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                        child: _buildCellText(
                          text: kStr,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1D4ED8),
                          ),
                          queryLower: queryLower,
                          nextMatchIndex: () => matchCounter++,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        child: _buildCellText(
                          text: vStr,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
                            color: Color(0xFF1E293B),
                          ),
                          queryLower: queryLower,
                          nextMatchIndex: () => matchCounter++,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        _notifyAndScrollIfNeeded(matchCounter, queryLower);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTableToolbar(
              candidates: const [],
              activeCandidate: null,
              rowCount: entries.length,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        border: Border(
                            bottom: BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 52,
                            child: Center(
                              child: Text('#',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF475569))),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text('字段名',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF475569))),
                            ),
                          ),
                          Expanded(
                            flex: 7,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text('字段值',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF475569))),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(children: rows),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }

      return const Center(
        child: Text(
          '当前响应无数组或对象字段可展示为表格',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
        ),
      );
    }

    // 优先匹配选中的数组路径；否则优先选择首个包含对象元素的非空数组
    JsonArrayCandidate activeCandidate = candidates.firstWhere(
      (c) => c.path == widget.selectedArrayPath,
      orElse: () => candidates.firstWhere(
        (c) => c.items.isNotEmpty && c.items.first is Map,
        orElse: () => candidates.firstWhere(
          (c) => c.items.isNotEmpty,
          orElse: () => candidates.first,
        ),
      ),
    );

    final items = activeCandidate.items;
    final columns = <String>[];
    bool hasPrimitiveElement = false;

    for (final item in items) {
      if (item is Map) {
        for (final k in item.keys) {
          final keyStr = k.toString();
          if (!columns.contains(keyStr)) {
            columns.add(keyStr);
          }
        }
      } else {
        hasPrimitiveElement = true;
      }
    }
    if (columns.isEmpty || hasPrimitiveElement) {
      if (!columns.contains('value')) {
        columns.insert(0, 'value');
      }
    }

    const double indexColWidth = 52.0;
    const double dataColWidth = 175.0;
    final totalTableWidth =
        indexColWidth + (columns.length * dataColWidth);

    final headerCells = <Widget>[
      Container(
        width: indexColWidth,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: const Text(
          '#',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF475569),
          ),
        ),
      ),
      for (final col in columns)
        Container(
          width: dataColWidth,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: _buildCellText(
            text: col,
            style: const TextStyle(
              fontSize: 11.5,
              fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
            queryLower: queryLower,
            nextMatchIndex: () => matchCounter++,
          ),
        ),
    ];

    final dataRows = <Widget>[];
    for (int rowIdx = 0; rowIdx < items.length; rowIdx++) {
      final item = items[rowIdx];
      dataRows.add(
        Container(
          decoration: BoxDecoration(
            color: rowIdx.isEven ? Colors.white : const Color(0xFFF8FAFC),
            border: const Border(
              bottom: BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: indexColWidth,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    border:
                        Border(right: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: Text(
                    '${rowIdx + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
                for (final col in columns)
                  Container(
                    width: dataColWidth,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    alignment: Alignment.centerLeft,
                    decoration: const BoxDecoration(
                      border:
                          Border(right: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: _buildCellText(
                      text: item is Map
                          ? (item.containsKey(col)
                              ? _formatCellValue(item[col])
                              : '')
                          : (col == 'value' ? _formatCellValue(item) : ''),
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
                        color: Color(0xFF334155),
                      ),
                      queryLower: queryLower,
                      nextMatchIndex: () => matchCounter++,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    _notifyAndScrollIfNeeded(matchCounter, queryLower);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTableToolbar(
          candidates: candidates,
          activeCandidate: activeCandidate,
          rowCount: items.length,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            clipBehavior: Clip.antiAlias,
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      '该数组为空 []',
                      style:
                          TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                    ),
                  )
                : Scrollbar(
                    controller: _horizontalController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _horizontalController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: totalTableWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              decoration: const BoxDecoration(
                                color: Color(0xFFF1F5F9),
                                border: Border(
                                  bottom:
                                      BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                              ),
                              child: Row(children: headerCells),
                            ),
                            Expanded(
                              child: Scrollbar(
                                controller: _verticalController,
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  controller: _verticalController,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: dataRows,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTableToolbar({
    required List<JsonArrayCandidate> candidates,
    required JsonArrayCandidate? activeCandidate,
    required int rowCount,
  }) {
    return Row(
      children: [
        const Icon(Icons.table_chart_rounded,
            size: 15, color: Color(0xFF2563EB)),
        const SizedBox(width: 6),
        const Text(
          '表格节点:',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(width: 6),
        if (candidates.length > 1 && activeCandidate != null)
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: activeCandidate.path,
                isDense: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 15, color: Color(0xFF2563EB)),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1D4ED8),
                ),
                items: candidates
                    .map(
                      (c) => DropdownMenuItem<String>(
                        value: c.path,
                        child: Text(c.label),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    widget.onArrayPathChanged?.call(val);
                  }
                },
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Text(
              activeCandidate?.label ?? '根对象 · $rowCount 项',
              style: const TextStyle(
                fontSize: 11,
                fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1D4ED8),
              ),
            ),
          ),
        const Spacer(),
        if (widget.onSwitchToJson != null)
          InkWell(
            onTap: widget.onSwitchToJson,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.data_object_rounded,
                      size: 13, color: Color(0xFF475569)),
                  SizedBox(width: 4),
                  Text(
                    '返回 JSON 视图',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
