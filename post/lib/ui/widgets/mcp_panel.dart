import 'dart:convert';
import '../app_fonts.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/mcp_server_service.dart';

class McpPanel extends StatefulWidget {
  final McpServerService mcpServerService;
  final VoidCallback onStateChanged;

  const McpPanel({
    super.key,
    required this.mcpServerService,
    required this.onStateChanged,
  });

  @override
  State<McpPanel> createState() => _McpPanelState();
}

class _McpPanelState extends State<McpPanel> {
  String _selectedTool = 'list_collections_and_apis';
  final TextEditingController _paramsController = TextEditingController();
  String _toolOutput = '';
  bool _isExecuting = false;

  final Map<String, String> _toolDefaultParams = {
    'list_collections_and_apis': '{}',
    'get_api_detail': '{"request_id": "req-get-user"}',
    'execute_api_request':
        '{"url": "/get", "method": "GET", "headers": {"X-Agent": "MCP"}}',
    'upsert_api_request':
        '{"name": "示例接口", "method": "POST", "url": "/api/demo", "folder_path": "测试目录"}',
    'manage_api_request':
        '{"action": "duplicate", "request_id": "req-get-user"}',
    'manage_containers':
        '{"action": "get_detail", "container_id": "col-demo"}',
    'manage_environment_variables': '{"action": "get_variables"}',
    'get_execution_history_logs': '{"log_type": "all", "limit": 5}',
  };

  @override
  void initState() {
    super.initState();
    _paramsController.text = _toolDefaultParams[_selectedTool] ?? '{}';
  }

  void _copyConfig() {
    final config = {
      'mcpServers': {
        'mindpost': {
          'url': 'http://127.0.0.1:${widget.mcpServerService.port}/sse',
        }
      }
    };
    Clipboard.setData(ClipboardData(
      text: const JsonEncoder.withIndent('  ').convert(config),
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制 Cursor / Claude MCP 接入配置到剪贴板！')),
    );
  }

  Future<void> _executeTool() async {
    setState(() {
      _isExecuting = true;
      _toolOutput = '';
    });

    try {
      final params = json.decode(_paramsController.text);
      final jsonRpcReq = {
        'jsonrpc': '2.0',
        'id': 'test-${DateTime.now().millisecondsSinceEpoch}',
        'method': 'tools/call',
        'params': {
          'name': _selectedTool,
          'arguments': params,
        },
      };

      // 直接调用 MCP Service 处理逻辑
      final client = HttpClient();
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${widget.mcpServerService.port}/mcp'),
      );
      req.headers.contentType = ContentType.json;
      req.write(json.encode(jsonRpcReq));
      final res = await req.close();
      final resBody = await utf8.decodeStream(res);

      setState(() {
        final decoded = json.decode(resBody);
        _toolOutput = const JsonEncoder.withIndent('  ').convert(decoded);
      });
    } catch (e) {
      setState(() {
        _toolOutput = '执行异常: $e';
      });
    } finally {
      setState(() {
        _isExecuting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = widget.mcpServerService.isRunning;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        width: 860,
        height: 620,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hub_outlined, color: Color(0xFF10B981), size: 24),
                const SizedBox(width: 8),
                const Text(
                  'MCP 调试控制台',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isRunning ? const Color(0xFF10B981) : Colors.grey)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isRunning ? const Color(0xFF10B981) : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isRunning
                            ? '运行中 :${widget.mcpServerService.port}'
                            : '已停止',
                        style: TextStyle(
                          color: isRunning ? const Color(0xFF10B981) : Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 操作栏与配置一览
                    Card(
                      elevation: 0,
                      color: Colors.grey.withValues(alpha: 0.06),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('端点地址:',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                                Text(
                                  'http://127.0.0.1:${widget.mcpServerService.port}/sse',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback),
                                ),
                              ],
                            ),
                            const Spacer(),
                            ElevatedButton.icon(
                              onPressed: _copyConfig,
                              icon: const Icon(Icons.copy, size: 14),
                              label: const Text('复制 Agent 接入配置',
                                  style: TextStyle(fontSize: 12)),
                            ),
                            const SizedBox(width: 8),
                            if (isRunning)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red),
                                onPressed: () async {
                                  await widget.mcpServerService.stopServer();
                                  widget.onStateChanged();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.stop, size: 16),
                                label: const Text('停止服务'),
                              )
                            else
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () async {
                                  await widget.mcpServerService.startServer();
                                  widget.onStateChanged();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.play_arrow, size: 16),
                                label: const Text('启动服务'),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 在线 MCP Tool 交互测试工具
                    const Text(
                      '🛠️ MCP Tools 在线自测与调试',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        DropdownButton<String>(
                          value: _selectedTool,
                          items: const [
                            DropdownMenuItem(
                              value: 'list_collections_and_apis',
                              child: Text('list_collections_and_apis · 列出集合与接口树'),
                            ),
                            DropdownMenuItem(
                              value: 'get_api_detail',
                              child: Text('get_api_detail · 获取接口与继承详情'),
                            ),
                            DropdownMenuItem(
                              value: 'execute_api_request',
                              child: Text('execute_api_request · 调度执行请求'),
                            ),
                            DropdownMenuItem(
                              value: 'upsert_api_request',
                              child: Text('upsert_api_request · 新增或局部更新接口'),
                            ),
                            DropdownMenuItem(
                              value: 'manage_api_request',
                              child: Text('manage_api_request · 删除/移动/复制接口'),
                            ),
                            DropdownMenuItem(
                              value: 'manage_containers',
                              child: Text('manage_containers · 集合/目录与公共配置'),
                            ),
                            DropdownMenuItem(
                              value: 'manage_environment_variables',
                              child:
                                  Text('manage_environment_variables · 环境与全局变量'),
                            ),
                            DropdownMenuItem(
                              value: 'get_execution_history_logs',
                              child: Text('get_execution_history_logs · 历史与审计日志'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedTool = val;
                                _paramsController.text =
                                    _toolDefaultParams[val] ?? '{}';
                              });
                            }
                          },
                        ),
                        const Spacer(),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: isRunning && !_isExecuting
                              ? _executeTool
                              : null,
                          icon: _isExecuting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send, size: 14),
                          label: Text(_isExecuting ? '调度中...' : '调用 Tool'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _paramsController,
                      maxLines: 3,
                      style: const TextStyle(
                          fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback, fontSize: 12),
                      decoration: const InputDecoration(
                        labelText: '入参 JSON',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    if (_toolOutput.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          _toolOutput,
                          style: const TextStyle(
                              fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback, fontSize: 11),
                        ),
                      ),
                    ],

                    const SizedBox(height: 18),
                    // 最近调用审计记录
                    const Text(
                      '📋 外部 Agent 实时调用审计日志',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (widget.mcpServerService.logs.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        alignment: Alignment.center,
                        child: Text(
                          '暂无外部 Agent 调度记录，支持 Cursor / Claude Desktop 直连',
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 12),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: widget.mcpServerService.logs.length,
                        itemBuilder: (context, index) {
                          final log = widget.mcpServerService.logs[index];
                          final isSuccess = log.status == 'SUCCESS';
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              isSuccess
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                              color: isSuccess ? Colors.green : Colors.red,
                              size: 18,
                            ),
                            title: Text(
                              '${log.toolName} (${log.time.hour.toString().padLeft(2, '0')}:${log.time.minute.toString().padLeft(2, '0')}:${log.time.second.toString().padLeft(2, '0')})',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            subtitle: Text(
                              'Params: ${json.encode(log.params)} \nResult: ${log.resultSummary}',
                              style: const TextStyle(
                                  fontSize: 11, fontFamily: AppFonts.codeFamily, fontFamilyFallback: AppFonts.codeFallback),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
