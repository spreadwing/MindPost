import 'package:flutter/material.dart';
import '../../models/workspace.dart';
import '../app_fonts.dart';

/// 帮助与文档中心弹窗
class HelpDialog extends StatefulWidget {
  final Workspace workspace;
  final VoidCallback onWorkspaceChanged;
  final int initialTab;

  const HelpDialog({
    super.key,
    required this.workspace,
    required this.onWorkspaceChanged,
    this.initialTab = 0,
  });

  static Future<void> show(
    BuildContext context, {
    required Workspace workspace,
    required VoidCallback onWorkspaceChanged,
    int initialTab = 0,
  }) {
    return showDialog(
      context: context,
      builder: (_) => HelpDialog(
        workspace: workspace,
        onWorkspaceChanged: onWorkspaceChanged,
        initialTab: initialTab,
      ),
    );
  }

  @override
  State<HelpDialog> createState() => _HelpDialogState();
}

class _HelpDialogState extends State<HelpDialog> {
  late int _selectedSection;

  @override
  void initState() {
    super.initState();
    _selectedSection = widget.initialTab.clamp(0, 5);
  }

  final List<Map<String, dynamic>> _navItems = const [
    {
      'icon': Icons.keyboard_outlined,
      'title': '交互与快捷键',
      'subtitle': '操作习惯设置与全量键盘快捷键速查',
    },
    {
      'icon': Icons.explore_outlined,
      'title': '快速上手指南',
      'subtitle': '集合层级、参数继承与接口调试流程',
    },
    {
      'icon': Icons.code_rounded,
      'title': '变量与内置函数',
      'subtitle': '动态插值语法、系统变量与前后置脚本',
    },
    {
      'icon': Icons.auto_awesome_outlined,
      'title': 'AI 助手与 MCP',
      'subtitle': '大模型智能体联调与内置标准协议',
    },
    {
      'icon': Icons.cloud_sync_outlined,
      'title': 'S3 云端多端同步',
      'subtitle': '私有对象存储跨设备漫游与配置',
    },
    {
      'icon': Icons.info_outline_rounded,
      'title': '关于 MindPost',
      'subtitle': '纯本地优先架构理念与版本特性',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final currentNav = _navItems[_selectedSection];

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 860,
        height: 620,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左侧分类导航条
            Container(
              width: 216,
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(
                  right: BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 20, 16, 16),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2563EB), Color(0xFF4F46E5)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Icon(
                            Icons.help_center_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '帮助中心',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              SizedBox(height: 1),
                              Text(
                                '文档与操作速查',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      itemCount: _navItems.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final item = _navItems[index];
                        final isSelected = _selectedSection == index;
                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            setState(() {
                              _selectedSection = index;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFEFF6FF)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFFBFDBFE)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  item['icon'] as IconData,
                                  size: 18,
                                  color: isSelected
                                      ? const Color(0xFF2563EB)
                                      : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    item['title'] as String,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? const Color(0xFF1D4ED8)
                                          : const Color(0xFF334155),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // 右侧内容区
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 顶部标题栏
                  Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                currentNav['title'] as String,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                currentNav['subtitle'] as String,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          icon: const Icon(Icons.close_rounded, size: 19),
                          color: const Color(0xFF64748B),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),

                  // 内容展示区
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(22),
                      child: _buildSectionContent(_selectedSection),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionContent(int section) {
    switch (section) {
      case 0:
        return _buildInteractionSection();
      case 1:
        return _buildGettingStartedSection();
      case 2:
        return _buildVariablesSection();
      case 3:
        return _buildAiAndMcpSection();
      case 4:
        return _buildS3SyncSection();
      case 5:
      default:
        return _buildAboutSection();
    }
  }

  // ---------------------------------------------------------------------------
  // 分区 0：交互与快捷键（原设置移入 + 详尽补充）
  // ---------------------------------------------------------------------------
  Widget _buildInteractionSection() {
    final globalShortcuts = <Map<String, String>>[
      {
        'keys': 'Ctrl + S',
        'desc': '保存当前打开的接口或目录配置标签页，清除标签页未保存圆点标记',
      },
      {
        'keys': 'Ctrl + F',
        'desc': '在底部响应面板激活搜索框，支持关键字实时高亮与匹配项导航',
      },
      {
        'keys': 'Esc',
        'desc': '快速关闭响应搜索高亮面板，或在模态弹窗打开时退出弹窗',
      },
      {
        'keys': 'Enter',
        'desc': '在响应搜索框中向下跳转聚焦到下一个高亮匹配项',
      },
      {
        'keys': 'Shift + Enter',
        'desc': '在响应搜索框中向上跳转聚焦到上一个高亮匹配项',
      },
      {
        'keys': 'Tab',
        'desc': '在 Query 参数、Headers、环境变量表格中顺序切换至下一个输入框',
      },
    ];

    final tabShortcuts = <Map<String, String>>[
      {
        'keys': '双击标签页',
        'desc': '若开启下方开关，双击顶部任意已打开的标签页即可将其快速关闭',
      },
      {
        'keys': '右键标签页',
        'desc': '呼出标签页右键菜单，支持「关闭当前」、「关闭其他」、「关闭右侧」及「全部关闭」',
      },
      {
        'keys': '单击标签页',
        'desc': '即时激活该标签页，并在工作区载入对应接口或目录的编辑界面',
      },
      {
        'keys': '拖动分割线',
        'desc': '鼠标拖拽左侧树形栏右边缘或响应区上边缘，可自由调整侧边栏宽度与面板高度',
      },
    ];

    final treeShortcuts = <Map<String, String>>[
      {
        'keys': '单击左侧目录',
        'desc': '打开该目录公共配置页，设置公共 Headers、Query 参数与前后置继承脚本',
      },
      {
        'keys': '双击左侧目录',
        'desc': '快速展开或折叠该目录节点及其下属的各级子目录与接口列表',
      },
      {
        'keys': '右键目录 / 接口',
        'desc': '呼出管理菜单，支持新建子接口、新建子目录、重命名、复制 cURL、克隆与删除',
      },
      {
        'keys': '鼠标悬浮操作项',
        'desc': '在目录树右侧会显示快速新建接口与子目录的操作按钮，提升高频创建效率',
      },
    ];

    final responseShortcuts = <Map<String, String>>[
      {
        'keys': '右键响应数组节点',
        'desc': '在 JSON 响应结构树中右击任意 Array 字段，一键切换为二维可视化表格视图',
      },
      {
        'keys': '点击状态码与耗时',
        'desc': '点击响应状态条，弹出耗时瀑布流（DNS解析、TCP连接、首字节TTFB、下载耗时）',
      },
      {
        'keys': '格式化 JSON 请求体',
        'desc': '在 Body 为 JSON 格式时，点击右上角「格式化」按钮自动规范缩进与排版',
      },
      {
        'keys': '右侧 cURL 导出',
        'desc': '展开右侧工具栏「cURL」面板，实时生成标准终端请求命令并支持一键复制',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('鼠标与标签页交互配置'),
        const SizedBox(height: 10),
        _buildSwitchCard(
          icon: Icons.tab_unselected_rounded,
          title: '双击标签页关闭',
          subtitle: '开启后，鼠标左键双击顶部任意打开的标签页即可快速将其关闭',
          value: widget.workspace.doubleClickToCloseTab,
          onChanged: (val) {
            setState(() {
              widget.workspace.doubleClickToCloseTab = val;
            });
            widget.onWorkspaceChanged();
          },
        ),
        const SizedBox(height: 10),
        _buildSwitchCard(
          icon: Icons.visibility_outlined,
          title: '显示解析后请求目标栏',
          subtitle: '在请求地址输入框下方实时展示环境变量与动态函数替换后的完整实际请求 URL',
          value: widget.workspace.showUrlPreviewBar,
          onChanged: (val) {
            setState(() {
              widget.workspace.showUrlPreviewBar = val;
            });
            widget.onWorkspaceChanged();
          },
        ),
        const SizedBox(height: 24),
        _buildSectionTitle('常用全局快捷键速查'),
        const SizedBox(height: 10),
        _buildShortcutTable(globalShortcuts),
        const SizedBox(height: 24),
        _buildSectionTitle('标签页与工作区操作'),
        const SizedBox(height: 10),
        _buildShortcutTable(tabShortcuts),
        const SizedBox(height: 24),
        _buildSectionTitle('左侧目录树交互'),
        const SizedBox(height: 10),
        _buildShortcutTable(treeShortcuts),
        const SizedBox(height: 24),
        _buildSectionTitle('响应结果与数据分析'),
        const SizedBox(height: 10),
        _buildShortcutTable(responseShortcuts),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 分区 1：快速上手指南
  // ---------------------------------------------------------------------------
  Widget _buildGettingStartedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoBanner(
          icon: Icons.rocket_launch_rounded,
          title: '欢迎使用 MindPost',
          content:
              'MindPost 是一款面向现代开发者的纯本地、高颜值、极速 API 调试工作台。数据完全落盘本地，无需登录账号，冷启动瞬时就绪，深度集成环境变量、AI 智能助手与原生 MCP 协议。',
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('1. 接口与集合组织架构'),
        const SizedBox(height: 8),
        _buildCard(
          children: [
            _buildTextParagraph(
                '• 集合（Collection）：顶级业务分类，例如「用户中心」、「交易服务」等，每个集合下可建立多级分组目录。'),
            _buildTextParagraph(
                '• 目录分组（Folder）：支持无限制的多级嵌套，每个目录均可拥有自身的「公共请求头」、「公共 Query 参数」以及「前后置处理脚本」。'),
            _buildTextParagraph(
                '• 接口定义（API Request）：挂载在目录或集合之下，自动继承所有父级目录配置的公共参数，无需在每个接口重复填写。'),
          ],
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('2. 标准调试全流程'),
        const SizedBox(height: 8),
        _buildCard(
          children: [
            _buildStepRow(
              step: '1',
              title: '选择 HTTP 方法与输入地址',
              desc:
                  '支持 GET、POST、PUT、DELETE、PATCH、HEAD、OPTIONS 等全套方法。URL 支持输入 {{baseUrl}}/api/v1/users 等带变量的动态地址。',
            ),
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            _buildStepRow(
              step: '2',
              title: '配置请求参数与请求体',
              desc:
                  '在中间面板配置 Params（Query参数）、Headers、Auth（认证令牌）以及 Body（支持 JSON、Form-Data、x-www-form-urlencoded、Raw）。',
            ),
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            _buildStepRow(
              step: '3',
              title: '点击发送并即时分析结果',
              desc:
                  '点击右侧醒目的「发送」按钮。底部响应区即时展示 HTTP 状态码、耗时统计与响应体，提供树状 JSON、Raw 源码、二维表格等多种视图。',
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('3. 历史记录与快速回放'),
        const SizedBox(height: 8),
        _buildCard(
          children: [
            _buildTextParagraph(
                '点击左侧功能栏的「历史」按钮，可查看最近执行过的所有 API 调用。系统会自动去重并按最新调用时间倒序排列，点击任意历史记录即可一键还原请求上下文重新发送。'),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 分区 2：变量与内置函数
  // ---------------------------------------------------------------------------
  Widget _buildVariablesSection() {
    final systemVars = <Map<String, String>>[
      {
        'name': '{{\$guid}} / {{\$uuid}}',
        'example': 'd3b07384-d113-46fb-a0aa-9a7852b7a974',
        'desc': '自动生成随机的标准 UUID v4 唯一识别码',
      },
      {
        'name': '{{\$timestamp}}',
        'example': '1718000000000',
        'desc': '自动获取当前 Unix 毫秒级时间戳（13 位长整型）',
      },
      {
        'name': '{{\$isoTimestamp}}',
        'example': '2026-10-16T08:30:00.000Z',
        'desc': '自动生成标准的 ISO 8601 UTC 日期时间字符串',
      },
      {
        'name': '{{\$randomInt}}',
        'example': '4829',
        'desc': '随机生成 0 ~ 9999 之间的整数字符串',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('双大括号插值语法'),
        const SizedBox(height: 8),
        _buildCard(
          children: [
            _buildTextParagraph(
                '在任何请求的 URL 地址、Query 参数、Header 键值或 JSON 请求体中，只要输入双大括号 {{variable_name}}，MindPost 就会在发送请求前自动将其替换为真实值。'),
            const SizedBox(height: 8),
            _buildCodeSnippet(
              '// 示例 1: URL 中的变量插值\n'
              '{{baseUrl}}/api/v1/user/profile?tenantId={{currentTenant}}\n\n'
              '// 示例 2: Headers 中的认证令牌\n'
              'Authorization: Bearer {{accessToken}}',
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('作用域优先级'),
        const SizedBox(height: 8),
        _buildCard(
          children: [
            _buildTextParagraph('变量名称相同时，系统遵循以下优先级自动覆盖解析：'),
            const SizedBox(height: 4),
            _buildTextParagraph('  1. 接口/目录局部临时变量（最高优先级）'),
            _buildTextParagraph('  2. 当前已激活环境的变量（如开发环境、生产环境）'),
            _buildTextParagraph('  3. 全局共享变量（最低优先级）'),
          ],
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('系统内置动态变量'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: List.generate(systemVars.length, (i) {
              final item = systemVars[i];
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: Text(
                            item['name']!,
                            style: AppFonts.code(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF2563EB),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['desc']!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '示例生成值: ${item['example']!}',
                                style: AppFonts.code(
                                  fontSize: 11,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (i < systemVars.length - 1)
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                ],
              );
            }),
          ),
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('顶部枚举变量快捷切换'),
        const SizedBox(height: 8),
        _buildCard(
          children: [
            _buildTextParagraph(
                '在「管理环境变量」弹窗中，勾选某个变量的「是否枚举」与「在顶栏显示」，顶部导航栏就会立即出现该变量的快捷下拉菜单。在多租户系统或联调不同角色账号时，无需进入弹窗即可在顶栏秒级切换！'),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 分区 3：AI 助手与 MCP 协议
  // ---------------------------------------------------------------------------
  Widget _buildAiAndMcpSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('AI 智能助手 (Copilot)'),
        const SizedBox(height: 8),
        _buildCard(
          children: [
            _buildTextParagraph(
                'MindPost 原生支持接入任何兼容 OpenAI 规范的现代大模型（例如 DeepSeek-V3/R1、通义千问、Kimi、ChatGPT、Claude 兼容网关等）。'),
            const SizedBox(height: 6),
            _buildTextParagraph('• 如何开启：进入「设置」->「AI 助手配置」，填入 API Base URL 与 API Key 并保存。'),
            _buildTextParagraph(
                '• 界面入口：配置完成后，工作台最右侧会自动出现紫色的「AI」抽屉按钮，点击即可展开对话面板。'),
            _buildTextParagraph(
                '• 核心功能：智能分析接口 4xx/5xx 报错根因、自动根据接口信息编写请求体用例、一键提炼 JSON Schema、生成 Dart/TS 类型定义。'),
          ],
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('内置标准 MCP (Model Context Protocol) 协议'),
        const SizedBox(height: 8),
        _buildCard(
          children: [
            _buildTextParagraph(
                'MindPost 创新性地在桌面端内嵌了标准 MCP 服务（默认监听 3333 端口）。这意味着外部智能体（如 Claude Desktop、Cursor、Antigravity、VSCode AI 等）能够直接与 MindPost 联动，自主读取当前工作区的所有 API 定义与环境变量！'),
            const SizedBox(height: 10),
            _buildTextParagraph('在 Claude Desktop 或外部工具的配置文件中添加以下配置即可接入：'),
            const SizedBox(height: 6),
            _buildCodeSnippet(
              '{\n'
              '  "mcpServers": {\n'
              '    "mindpost": {\n'
              '      "command": "curl",\n'
              '      "args": ["http://127.0.0.1:3333/mcp"]\n'
              '    }\n'
              '  }\n'
              '}',
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 分区 4：S3 云端多端同步
  // ---------------------------------------------------------------------------
  Widget _buildS3SyncSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoBanner(
          icon: Icons.shield_outlined,
          title: '为什么采用 S3 协议进行云端同步？',
          content:
              '传统 API 工具强制将用户接口上传到第三方商业云服务器，存在严重的商业机密泄露与合规审查风险。MindPost 采用通用的 S3 标准对象存储协议，数据端到端完全由您掌控。',
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('广泛兼容的主流云存储'),
        const SizedBox(height: 8),
        _buildCard(
          children: [
            _buildTextParagraph(
                '• 本地私有自建：MinIO、Ceph、Rust-S3 等私有化集群，企业内网绝对隔离。'),
            _buildTextParagraph(
                '• 公有云对象存储：AWS S3、Cloudflare R2（免费额度大、无出口流量费）、阿里云 OSS、腾讯云 COS、华为云 OBS 等。'),
          ],
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('快速配置步骤'),
        const SizedBox(height: 8),
        _buildCard(
          children: [
            _buildStepRow(
              step: '1',
              title: '进入 S3 设置',
              desc: '点击顶部导航栏「同步」下拉菜单中的「S3 同步配置」，或进入软件设置中的「S3 云端同步」。',
            ),
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            _buildStepRow(
              step: '2',
              title: '填写连接凭证',
              desc:
                  '输入您的 Endpoint（如 https://s3.us-east-1.amazonaws.com 或 MinIO 地址）、Bucket 名称、Region、AccessKey 与 SecretKey。',
            ),
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            _buildStepRow(
              step: '3',
              title: '一键测试并开始同步',
              desc:
                  '点击「测试连接」，确认通过后点击「保存配置」。随后即可随时在顶部栏点击「上传同步到 S3」或「从 S3 拉取同步」实现多端漫游。',
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 分区 5：关于 MindPost
  // ---------------------------------------------------------------------------
  Widget _buildAboutSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFEFF6FF), Color(0xFFF8FAFC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Row(
            children: [
              Image.asset(
                'assets/app_logo.png',
                width: 52,
                height: 52,
                filterQuality: FilterQuality.medium,
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MindPost Desktop',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '版本 v1.0.0 · 纯本地优先、现代极速 API 调试工作台',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('设计理念与核心优势'),
        const SizedBox(height: 8),
        _buildCard(
          children: [
            _buildTextParagraph(
                '⚡ 极致轻量与瞬时响应：基于 Flutter 原生编译引擎，告别臃肿的 Electron 资源消耗，秒级冷启，极速发包。'),
            _buildTextParagraph(
                '🔒 零隐私追踪：所有接口、环境、变量与调用历史纯本地存储在 SQLite/JSON 文件中，无任何后台数据上传。'),
            _buildTextParagraph(
                '🧩 原生 MCP 赋能：内置标准 Model Context Protocol Server，为开发者的 AI 智能体应用赋能。'),
            _buildTextParagraph(
                '🌐 开放云漫游：拥抱开源标准的 S3 对象存储多端同步，拒绝被商业云平台厂商绑定。'),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 辅助 UI 构建组件
  // ---------------------------------------------------------------------------
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: Color(0xFF0F172A),
      ),
    );
  }

  Widget _buildSwitchCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.82,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: const Color(0xFF2563EB),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutTable(List<Map<String, String>> shortcuts) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: List.generate(shortcuts.length, (index) {
          final item = shortcuts[index];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Container(
                      constraints: const BoxConstraints(minWidth: 120),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0A000000),
                            offset: Offset(0, 1),
                            blurRadius: 1,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        item['keys']!,
                        style: AppFonts.code(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        item['desc']!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (index < shortcuts.length - 1)
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildTextParagraph(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF334155),
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildStepRow({
    required String step,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB),
            borderRadius: BorderRadius.circular(5),
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF64748B),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCodeSnippet(String code) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SelectableText(
        code,
        style: AppFonts.code(
          fontSize: 11,
          color: const Color(0xFFE2E8F0),
          height: 1.45,
        ),
      ),
    );
  }

  Widget _buildInfoBanner({
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF2563EB)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1D4ED8),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF1E40AF),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
