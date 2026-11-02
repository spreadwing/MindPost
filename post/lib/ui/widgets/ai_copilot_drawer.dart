import 'dart:convert';
import '../app_fonts.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../models/api_request.dart';
import '../../models/workspace.dart';

class AiCopilotDrawer extends StatefulWidget {
  final ApiRequest? activeRequest;
  final AiConfig? aiConfig;
  final VoidCallback onRequestUpdated;
  final VoidCallback? onClose;
  final VoidCallback? onOpenAiSettings;

  const AiCopilotDrawer({
    super.key,
    required this.activeRequest,
    this.aiConfig,
    required this.onRequestUpdated,
    this.onClose,
    this.onOpenAiSettings,
  });

  @override
  State<AiCopilotDrawer> createState() => _AiCopilotDrawerState();
}

class _AiCopilotDrawerState extends State<AiCopilotDrawer> {
  final TextEditingController _promptController = TextEditingController();
  bool _isGenerating = false;
  final List<Map<String, String>> _messages = [
    {
      'role': 'assistant',
      'content':
          '你好！我是 MindPost 智能助手。\n我可以协助你生成 API 请求定义、编写 HMAC 签名脚本或构造后置断言。你可以点击下方的快捷建议，或直接输入你的诉求。',
    }
  ];

  void _applyHmacScript() {
    if (widget.activeRequest == null) return;
    widget.activeRequest!.preRequestScript = '''// AI 生成：自动计算 HMAC-SHA256 签名并注入 Headers
const timestamp = Date.now();
const nonce = Math.random().toString(36).substring(2);
const secret = pm.environment.get("apiKey") || "default_secret";

// 构造待签名字符串
const rawSignStr = "timestamp=" + timestamp + "&nonce=" + nonce;
const sign = CryptoJS.HmacSHA256(rawSignStr, secret).toString();

// 注入请求头
pm.request.headers.add({ key: "X-Timestamp", value: timestamp });
pm.request.headers.add({ key: "X-Nonce", value: nonce });
pm.request.headers.add({ key: "X-Signature", value: sign });

console.log("签名计算成功: " + sign);''';
    widget.onRequestUpdated();
    setState(() {
      _messages.add({
        'role': 'assistant',
        'content': '已为当前接口写入【HMAC-SHA256 动态签名】前置脚本并自动注入请求头！',
      });
    });
  }

  void _applyAssertions() {
    if (widget.activeRequest == null) return;
    widget.activeRequest!.postRequestScript = '''// AI 生成：标准测试断言
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

pm.test("Response contains data", function () {
    var jsonData = pm.response.json();
    if (!jsonData) throw new Error("Response is empty");
});''';
    widget.onRequestUpdated();
    setState(() {
      _messages.add({
        'role': 'assistant',
        'content': '已为当前接口写入常用的状态码与 JSON 数据校验断言！',
      });
    });
  }

  Future<void> _sendUserPrompt() async {
    final text = _promptController.text.trim();
    if (text.isEmpty || _isGenerating) return;

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _promptController.clear();
      _isGenerating = true;
    });

    final cfg = widget.aiConfig;
    if (cfg != null && cfg.isConfigured) {
      try {
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 30),
        ));
        var endpoint = cfg.baseUrl.trim();
        if (endpoint.endsWith('/')) {
          endpoint = endpoint.substring(0, endpoint.length - 1);
        }
        if (!endpoint.endsWith('/chat/completions')) {
          endpoint = '$endpoint/chat/completions';
        }
        final reqContext = widget.activeRequest != null
            ? '当前正在调试的接口：${widget.activeRequest!.name} · ${widget.activeRequest!.method.nameString} ${widget.activeRequest!.url}'
            : '当前未选中具体接口';

        final response = await dio.post<dynamic>(
          endpoint,
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              if (cfg.apiKey.trim().isNotEmpty)
                'Authorization': 'Bearer ${cfg.apiKey.trim()}',
            },
          ),
          data: json.encode({
            'model': cfg.model.trim().isEmpty ? 'gpt-4o-mini' : cfg.model.trim(),
            'messages': [
              {
                'role': 'system',
                'content':
                    '你是 MindPost 接口调试工具内置的 AI 助手。请用简洁专业的中文解答 API 调试、前置 JavaScript 签名脚本 (支持 pm.environment、pm.request.headers、CryptoJS) 以及后置断言 (pm.test、pm.response) 问题。$reqContext',
              },
              {'role': 'user', 'content': text},
            ],
            'temperature': 0.3,
          }),
        );

        final data = response.data is String
            ? json.decode(response.data as String)
            : response.data;
        final reply = data['choices']?[0]?['message']?['content']?.toString();
        if (reply != null && reply.trim().isNotEmpty && mounted) {
          setState(() {
            _isGenerating = false;
            _messages.add({'role': 'assistant', 'content': reply.trim()});
          });
          return;
        }
      } catch (_) {
        // 回退到本地智能模板回复
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() {
      _isGenerating = false;
      if (text.contains('签名') || text.contains('前置') || text.contains('sign')) {
        _messages.add({
          'role': 'assistant',
          'content': '检测到你需要签名脚本，可点击下方按钮一键应用到当前接口的前置脚本中。',
        });
      } else if (text.contains('断言') || text.contains('测试')) {
        _messages.add({
          'role': 'assistant',
          'content': '检测到你需要测试断言，可点击下方按钮一键应用标准校验代码。',
        });
      } else {
        _messages.add({
          'role': 'assistant',
          'content':
              '已分析需求：“$text”。推荐使用环境占位符如 `{{baseUrl}}` 与动态标签 `{{\$timestamp}}` 保持接口灵活性。',
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final modelName = widget.aiConfig?.model.trim().isNotEmpty == true
        ? widget.aiConfig!.model.trim()
        : 'AI Copilot';

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: const Border(left: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: Color(0xFF7C3AED), size: 14),
                ),
                const SizedBox(width: 8),
                const Text(
                  'AI 助手',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Text(
                      modelName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                if (widget.onOpenAiSettings != null)
                  IconButton(
                    tooltip: 'AI 模型设置',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 26, minHeight: 26),
                    icon: const Icon(Icons.tune_rounded,
                        size: 15, color: Color(0xFF64748B)),
                    onPressed: widget.onOpenAiSettings,
                  ),
                IconButton(
                  tooltip: '收起面板',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 26, minHeight: 26),
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: Color(0xFF64748B)),
                  onPressed: () {
                    if (widget.onClose != null) {
                      widget.onClose!();
                    } else {
                      Navigator.of(context).maybePop();
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length + (_isGenerating ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: Color(0xFF7C3AED),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            '正在思考...',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final msg = _messages[index];
                final isUser = msg['role'] == 'user';
                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    constraints: const BoxConstraints(maxWidth: 265),
                    decoration: BoxDecoration(
                      color: isUser
                          ? const Color(0xFF2563EB)
                          : const Color(0xFFF8FAFC),
                      border: isUser
                          ? null
                          : Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      msg['content'] ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: isUser ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 快捷指令标签
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.code_rounded,
                      size: 13, color: Color(0xFF2563EB)),
                  label:
                      const Text('生成 HMAC 签名', style: TextStyle(fontSize: 11)),
                  onPressed: _applyHmacScript,
                  backgroundColor: const Color(0xFFF8FAFC),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                ActionChip(
                  avatar: const Icon(Icons.check_circle_outline_rounded,
                      size: 13, color: Color(0xFF10B981)),
                  label: const Text('生成测试断言', style: TextStyle(fontSize: 11)),
                  onPressed: _applyAssertions,
                  backgroundColor: const Color(0xFFF8FAFC),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ],
            ),
          ),
          // 输入框
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _promptController,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: '输入诉求，如“帮我写个鉴权”...',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendUserPrompt(),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.send_rounded, size: 16),
                  color: const Color(0xFF2563EB),
                  onPressed: _sendUserPrompt,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

