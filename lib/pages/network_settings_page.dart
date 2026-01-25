import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/network_logger.dart';
import '../services/network/doh/doh_resolver.dart';
import '../services/network/doh/network_settings_service.dart';
import 'network_adapter_settings_page.dart';

class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({super.key});

  @override
  State<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  final NetworkSettingsService _service = NetworkSettingsService.instance;
  final Map<String, int?> _latencies = {};
  final Set<String> _testingServers = {};
  bool _testingAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([_service.notifier, _service.isApplying]),
      builder: (context, _) {
        final settings = _service.notifier.value;
        final isApplying = _service.isApplying.value;
        return Scaffold(
          appBar: AppBar(
            title: const Text('网络设置'),
            actions: [
              if (isApplying)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (settings.dohEnabled)
                TextButton.icon(
                  onPressed: _testingAll ? null : _testAllServers,
                  icon: _testingAll
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.speed, size: 18),
                  label: Text(_testingAll ? '测速中' : '全部测速'),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // DOH 开关与状态
              _buildDohCard(theme, settings, isApplying),
              const SizedBox(height: 24),

              // 服务器列表
              _buildSectionHeader(theme, '服务器', trailing: _buildAddButton(theme)),
              const SizedBox(height: 12),
              _buildServerList(theme, settings),
              const SizedBox(height: 24),

              // 高级设置
              _buildSectionHeader(theme, '高级'),
              const SizedBox(height: 12),
              _buildAdvancedCard(theme),
              const SizedBox(height: 24),

              // 调试工具
              _buildSectionHeader(theme, '调试'),
              const SizedBox(height: 12),
              _buildDebugCard(theme),
              const SizedBox(height: 24),

              // 说明
              _buildHint(theme),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, {Widget? trailing}) {
    return Row(
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildAddButton(ThemeData theme) {
    return TextButton.icon(
      onPressed: _showAddServerDialog,
      icon: const Icon(Icons.add, size: 18),
      label: const Text('添加'),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  // ==================== 高级设置卡片 ====================

  Widget _buildAdvancedCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          if (!Platform.isWindows)
            ListTile(
              leading: const Icon(Icons.settings_ethernet),
              title: const Text('网络适配器'),
              subtitle: const Text('管理 Cronet 和备用适配器设置'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NetworkAdapterSettingsPage(),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ==================== DOH 开关卡片 ====================

  Widget _buildDohCard(ThemeData theme, NetworkSettings settings, bool isApplying) {
    final proxyService = _service.proxyService;
    final isRunning = proxyService.isRunning;
    final port = settings.proxyPort;
    final showLoading = isApplying
        || _service.pendingStart
        || (settings.dohEnabled && !isRunning && !_service.lastStartFailed);

    return Card(
      elevation: 0,
      color: settings.dohEnabled
          ? theme.colorScheme.primaryContainer.withOpacity(0.3)
          : theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: settings.dohEnabled
              ? theme.colorScheme.primary.withOpacity(0.3)
              : theme.colorScheme.outlineVariant.withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('DNS over HTTPS'),
            subtitle: Text(
              settings.dohEnabled ? '已启用加密 DNS 解析' : '使用系统默认 DNS',
            ),
            secondary: Icon(
              settings.dohEnabled ? Icons.shield : Icons.shield_outlined,
              color: settings.dohEnabled ? theme.colorScheme.primary : null,
            ),
            value: settings.dohEnabled,
            onChanged: (value) => _service.setDohEnabled(value),
          ),
          if (settings.dohEnabled) ...[
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.2)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: showLoading
                        ? _buildStatusChip(
                            theme,
                            key: const ValueKey('applying'),
                            customIcon: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            label: _service.wasRunningBeforeApply ? '正在重启...' : '正在启动...',
                            color: theme.colorScheme.primary,
                          )
                        : _buildStatusChip(
                            theme,
                            key: ValueKey('status_${isRunning}_${_service.lastStartFailed}'),
                            icon: isRunning
                                ? Icons.check_circle
                                : _service.lastStartFailed
                                    ? Icons.error
                                    : Icons.hourglass_top,
                            label: isRunning ? '代理运行中' : '代理未启动',
                            color: isRunning ? Colors.green : theme.colorScheme.error,
                          ),
                  ),
                  const SizedBox(width: 12),
                  if (port != null && isRunning)
                    _buildStatusChip(
                      theme,
                      icon: Icons.lan,
                      label: '端口 $port',
                      color: theme.colorScheme.secondary,
                    ),
                  if (isRunning) ...[
                    const Spacer(),
                    IconButton(
                      onPressed: isApplying ? null : _service.restartProxy,
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: '重启代理',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
            ),
            if (!isRunning && !isApplying && _service.lastStartFailed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 16, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '代理启动失败，DoH/ECH 无法生效',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: isApplying ? null : _service.restartProxy,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.2)),
            SwitchListTile(
              title: const Text('IPv6 优先'),
              subtitle: const Text('优先尝试 IPv6，失败自动回落 IPv4'),
              secondary: const Icon(Icons.language),
              value: settings.preferIPv6,
              onChanged: (value) => _service.setPreferIPv6(value),
              dense: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip(
    ThemeData theme, {
    Key? key,
    IconData? icon,
    Widget? customIcon,
    required String label,
    required Color color,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (customIcon != null)
            customIcon
          else if (icon != null)
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  // ==================== 服务器列表 ====================

  Widget _buildServerList(ThemeData theme, NetworkSettings settings) {
    final servers = _service.servers;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < servers.length; i++) ...[
            _buildServerTile(theme, servers[i], settings),
            if (i != servers.length - 1)
              Divider(height: 1, indent: 56, color: theme.colorScheme.outlineVariant.withOpacity(0.2)),
          ],
          if (servers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('暂无服务器'),
            ),
        ],
      ),
    );
  }

  Widget _buildServerTile(ThemeData theme, DohServer server, NetworkSettings settings) {
    final selected = server.url == settings.selectedServerUrl;
    final isTesting = _testingServers.contains(server.url);
    final latency = _latencies[server.url];

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 8, right: 12),
      leading: Radio<String>(
        value: server.url,
        groupValue: settings.selectedServerUrl,
        onChanged: (value) {
          if (value != null) _service.setSelectedServer(value);
        },
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              server.name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (server.isCustom)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '自定义',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        server.url,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 延迟显示
          if (isTesting)
            const SizedBox(
              width: 48,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (latency != null)
            SizedBox(
              width: 48,
              child: Text(
                '${latency}ms',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _getLatencyColor(latency),
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            )
          else
            SizedBox(
              width: 48,
              child: IconButton(
                icon: const Icon(Icons.speed, size: 20),
                tooltip: '测速',
                onPressed: () => _testServer(server),
                visualDensity: VisualDensity.compact,
              ),
            ),

          // 删除按钮（仅自定义服务器）
          if (server.isCustom)
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 20,
                color: theme.colorScheme.error,
              ),
              tooltip: '删除',
              onPressed: () => _confirmDeleteServer(server),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
      selected: selected,
      onTap: () => _service.setSelectedServer(server.url),
    );
  }

  Color _getLatencyColor(int latency) {
    if (latency < 100) return Colors.green;
    if (latency < 300) return Colors.orange;
    return Colors.red;
  }

  // ==================== 调试工具卡片 ====================

  Widget _buildDebugCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('查看日志'),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: _showLogSheet,
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.2)),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('分享日志'),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: _shareLogs,
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.2)),
          ListTile(
            leading: Icon(Icons.delete_sweep_outlined, color: theme.colorScheme.error),
            title: Text('清除日志', style: TextStyle(color: theme.colorScheme.error)),
            trailing: Icon(Icons.chevron_right, size: 20, color: theme.colorScheme.error),
            onTap: _clearLogs,
          ),
        ],
      ),
    );
  }

  Widget _buildHint(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '启用后会启动本地代理用于 DoH 解析。WebView 代理仅在 Android 生效。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 测速逻辑 ====================

  Future<void> _testServer(DohServer server) async {
    if (_testingServers.contains(server.url)) return;

    setState(() => _testingServers.add(server.url));

    final resolver = DohResolver(serverUrl: server.url, enableFallback: false);
    try {
      final ms = await resolver.testLatency(_service.testHost);
      if (mounted) {
        setState(() {
          _latencies[server.url] = ms;
          _testingServers.remove(server.url);
        });
      }
    } finally {
      resolver.dispose();
    }
  }

  Future<void> _testAllServers() async {
    if (_testingAll) return;
    setState(() => _testingAll = true);

    final servers = _service.servers;
    final futures = <Future<void>>[];

    for (final server in servers) {
      futures.add(_testServer(server));
    }

    await Future.wait(futures);

    if (mounted) {
      setState(() => _testingAll = false);
    }
  }

  // ==================== 对话框 ====================

  Future<void> _showAddServerDialog() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    final result = await showDialog<DohServer>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('添加服务器'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '例如：My DNS',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'DoH 地址',
                  hintText: 'https://dns.example.com/dns-query',
                ),
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final url = urlController.text.trim();
                if (name.isEmpty || url.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请填写完整信息')),
                  );
                  return;
                }
                if (!url.startsWith('https://')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('地址必须以 https:// 开头')),
                  );
                  return;
                }
                Navigator.pop(context, DohServer(name: name, url: url, isCustom: true));
              },
              child: const Text('添加'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      await _service.addCustomServer(result);
    }
  }

  Future<void> _confirmDeleteServer(DohServer server) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除服务器'),
        content: Text('确定要删除 "${server.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _service.removeCustomServer(server);
    }
  }

  // ==================== 日志功能 ====================

  Future<void> _showLogSheet() async {
    final logs = await NetworkLogger.readLogs();
    if (!mounted) return;

    final theme = Theme.of(context);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // 拖动条
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 标题栏
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        '调试日志',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: '复制',
                        onPressed: logs == null || logs.isEmpty
                            ? null
                            : () {
                                Clipboard.setData(ClipboardData(text: logs));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已复制到剪贴板')),
                                );
                              },
                      ),
                      IconButton(
                        icon: const Icon(Icons.share),
                        tooltip: '分享',
                        onPressed: logs == null || logs.isEmpty
                            ? null
                            : () {
                                Navigator.pop(context);
                                _shareLogs();
                              },
                      ),
                    ],
                  ),
                ),
                const Divider(),
                // 日志内容
                Expanded(
                  child: logs == null || logs.isEmpty
                      ? _buildEmptyLog(theme)
                      : SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            logs,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.5,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyLog(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.article_outlined,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无日志',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '启用 DOH 并发起请求后会产生日志',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareLogs() async {
    final logs = await NetworkLogger.readLogs();
    if (logs == null || logs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无日志可分享')),
      );
      return;
    }

    final path = await NetworkLogger.getLogPath();
    if (path != null) {
      await Share.shareXFiles([XFile(path)], subject: 'DOH 调试日志');
    } else {
      await Share.share(logs, subject: 'DOH 调试日志');
    }
  }

  Future<void> _clearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除日志'),
        content: const Text('确定要清除所有日志吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await NetworkLogger.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('日志已清除')),
        );
      }
    }
  }
}
