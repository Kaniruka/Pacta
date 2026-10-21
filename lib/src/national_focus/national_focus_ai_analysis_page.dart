import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'national_focus_ai_access.dart';

class NationalFocusAiAnalysisEntry extends StatelessWidget {
  const NationalFocusAiAnalysisEntry({
    super.key,
    required this.mcpUrl,
    required this.repository,
  });

  final String? mcpUrl;
  final NationalFocusAiGrantRepository? repository;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      key: const ValueKey('national-focus-ai-entry'),
      leading: const Icon(Icons.auto_awesome_outlined),
      title: const Text('国策 AI 分析'),
      subtitle: const Text('了解只读范围、配置 Codex，并管理授权'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => NationalFocusAiAnalysisPage(
            mcpUrl: mcpUrl,
            repository: repository,
          ),
        ),
      ),
    ),
  );
}

class NationalFocusAiAnalysisPage extends StatefulWidget {
  const NationalFocusAiAnalysisPage({
    super.key,
    required this.mcpUrl,
    required this.repository,
  });

  final String? mcpUrl;
  final NationalFocusAiGrantRepository? repository;

  @override
  State<NationalFocusAiAnalysisPage> createState() =>
      _NationalFocusAiAnalysisPageState();
}

class _NationalFocusAiAnalysisPageState
    extends State<NationalFocusAiAnalysisPage> {
  static const _serverName = 'pacta-national-focus';
  final _requestCodeController = TextEditingController();
  List<NationalFocusAiGrant> _grants = const [];
  NationalFocusAiAuthorizationRequest? _request;
  String? _inspectedRequestCode;
  String? _loadError;
  String? _actionMessage;
  bool _loading = true;
  bool _working = false;
  String? _workingGrantId;

  @override
  void initState() {
    super.initState();
    unawaited(_loadGrants());
  }

  @override
  void dispose() {
    _requestCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadGrants() async {
    final repository = widget.repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _loadError = null;
        _grants = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final grants = await repository.listMyGrants();
      if (!mounted) return;
      setState(() {
        _grants = grants;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _friendlyError(error);
      });
    }
  }

  Future<void> _inspectRequest() async {
    final repository = widget.repository;
    if (repository == null || _working) return;
    final requestCode = _requestCodeController.text.trim();
    if (!_isRequestCode(requestCode)) {
      setState(() => _actionMessage = '请输入浏览器显示的 64 位十六进制授权请求码。');
      return;
    }
    setState(() {
      _working = true;
      _actionMessage = null;
      _request = null;
      _inspectedRequestCode = null;
    });
    try {
      final request = await repository.inspectRequest(requestCode);
      if (!mounted) return;
      setState(() {
        _request = request;
        _inspectedRequestCode = requestCode;
      });
    } catch (error) {
      if (mounted) setState(() => _actionMessage = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _approveRequest() async {
    final repository = widget.repository;
    final requestCode = _inspectedRequestCode;
    if (repository == null || requestCode == null || _working) return;
    setState(() {
      _working = true;
      _actionMessage = null;
    });
    try {
      await repository.approveRequest(requestCode);
      if (!mounted) return;
      _requestCodeController.clear();
      setState(() {
        _request = null;
        _inspectedRequestCode = null;
        _actionMessage = '授权已完成。返回 Codex 浏览器继续连接；如果仍在等待，请刷新页面。';
      });
      await _loadGrants();
    } catch (error) {
      if (mounted) {
        setState(() {
          _actionMessage = _friendlyError(error);
          if (error is NationalFocusAiAccessError && error.code == '22023') {
            _request = null;
            _inspectedRequestCode = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _cancelRequest() {
    setState(() {
      _request = null;
      _inspectedRequestCode = null;
      _requestCodeController.clear();
      _actionMessage = '已取消；没有授予授权。';
    });
  }

  Future<void> _revokeGrant(NationalFocusAiGrant grant) async {
    final repository = widget.repository;
    if (repository == null || _working) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤销 Codex 连接？'),
        content: const Text('撤销后，Codex 的后续读取会被阻止。已经进入 Codex 对话的信息无法收回。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('保留连接'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _working = true;
      _workingGrantId = grant.id;
      _actionMessage = null;
    });
    try {
      await repository.revokeGrant(grant.id);
      if (!mounted) return;
      setState(() => _actionMessage = '连接已撤销。');
      await _loadGrants();
    } catch (error) {
      if (mounted) setState(() => _actionMessage = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _workingGrantId = null;
        });
      }
    }
  }

  Future<void> _copyCodexConfiguration() async {
    final mcpUrl = widget.mcpUrl;
    if (mcpUrl == null || mcpUrl.isEmpty) return;
    final config = _codexConfiguration(mcpUrl);
    await Clipboard.setData(ClipboardData(text: config));
    if (mounted) {
      setState(
        () => _actionMessage = '已复制 Codex 配置。配置只含服务地址，不含密钥或 Pacta 登录会话。',
      );
    }
  }

  String _friendlyError(Object error) {
    if (error is NationalFocusAiAccessError) {
      return switch (error.code) {
        '22023' => '授权请求码无效、已过期或已处理。请回到 Codex 浏览器刷新，再输入新的请求码。',
        '42501' => '当前登录状态无法管理授权。请重新登录，或确认账号未停用。',
        _ => '暂时无法连接授权服务。请检查网络与登录状态后重试。',
      };
    }
    return '暂时无法连接授权服务。请检查网络与登录状态后重试。';
  }

  @override
  Widget build(BuildContext context) {
    final mcpUrl = widget.mcpUrl;
    return Scaffold(
      key: const ValueKey('national-focus-ai-analysis-page'),
      appBar: AppBar(title: const Text('国策 AI 分析')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '只读连接',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '当前只开放最近一次手动上传的云快照元数据：版本、来源设备和上传时间。国策内容读取尚未开放。',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '你在 App 维护数据并手动上传后，Codex 才能读取新版本；打开此页或授权不会触发业务同步。',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '授权独立于 Pacta 登录会话。Codex 不会收到你的 Pacta 密码或普通应用会话；你可以随时撤销。撤销不能收回已进入对话的信息。',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _sectionTitle(context, '授权状态')),
                    IconButton(
                      tooltip: '刷新授权状态',
                      onPressed:
                          _loading || _working || widget.repository == null
                          ? null
                          : _loadGrants,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                _buildGrantStatus(context),
                const SizedBox(height: 12),
                _sectionTitle(context, '连接 Codex'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('在已安装 Codex CLI 的设备上复制并运行以下配置：'),
                        const SizedBox(height: 8),
                        if (mcpUrl == null || mcpUrl.isEmpty)
                          const Text('服务地址尚未配置，请联系应用维护者。')
                        else ...[
                          Text(
                            'MCP 服务地址',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          SelectableText(mcpUrl),
                          const SizedBox(height: 12),
                          SelectableText(_codexConfiguration(mcpUrl)),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: _working
                                ? null
                                : _copyCodexConfiguration,
                            icon: const Icon(Icons.copy_outlined),
                            label: const Text('复制 Codex 配置'),
                          ),
                        ],
                        const SizedBox(height: 8),
                        const Text(
                          '首次登录会在浏览器打开 Pacta 授权。将浏览器显示的一次性请求码粘贴到下方，在 App 核对客户端后明确授权。请求码 5 分钟有效且只能使用一次。',
                        ),
                        const SizedBox(height: 8),
                        const Text('授权有效 30 分钟且不自动续期；到期后在 Codex 重新运行登录命令。'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _sectionTitle(context, '确认授权请求'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('只输入 Codex 浏览器显示的一次性请求码。此码不会保存在 App 中。'),
                        const SizedBox(height: 12),
                        TextField(
                          key: const ValueKey('national-focus-ai-request-code'),
                          controller: _requestCodeController,
                          enabled: !_working && widget.repository != null,
                          maxLength: 64,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.visiblePassword,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp('[0-9a-fA-F]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            labelText: '授权请求码',
                            helperText: '64 位十六进制字符',
                          ),
                          onChanged: (_) => setState(() {
                            _request = null;
                            _inspectedRequestCode = null;
                            _actionMessage = null;
                          }),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed:
                                _working ||
                                    widget.repository == null ||
                                    !_isRequestCode(
                                      _requestCodeController.text.trim(),
                                    )
                                ? null
                                : _inspectRequest,
                            icon: const Icon(Icons.verified_user_outlined),
                            label: Text(_working ? '正在核对…' : '核对授权码'),
                          ),
                        ),
                        if (_request case final request?) ...[
                          const Divider(height: 28),
                          Text(
                            '请求客户端',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          SelectableText(request.clientName),
                          const SizedBox(height: 12),
                          Text(
                            '授权范围',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          const Text('国策 AI 只读；当前仅可读取云快照元数据。'),
                          const SizedBox(height: 12),
                          Text(
                            '授权后返回地址',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          SelectableText(request.redirectUri),
                          const SizedBox(height: 16),
                          const Text('授权后 Codex 可在 30 分钟内读取上述范围，你可随时在此页撤销。'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _working ? null : _approveRequest,
                            child: Text(_working ? '正在授权…' : '授予 30 分钟只读授权'),
                          ),
                          TextButton(
                            onPressed: _working ? null : _cancelRequest,
                            child: const Text('取消，不授权'),
                          ),
                        ],
                        if (_actionMessage != null) ...[
                          const SizedBox(height: 8),
                          Semantics(
                            liveRegion: true,
                            child: Text(_actionMessage!),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrantStatus(BuildContext context) {
    final repository = widget.repository;
    if (repository == null) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.cloud_off_outlined),
          title: Text('连接状态不可用'),
          subtitle: Text('当前未配置服务或登录会话，请联系应用维护者。'),
        ),
      );
    }
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_loadError != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('无法读取授权状态'),
          subtitle: Text(_loadError!),
          trailing: TextButton.icon(
            onPressed: _working ? null : _loadGrants,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ),
      );
    }
    if (_grants.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.no_accounts_outlined),
          title: Text('尚未授权'),
          subtitle: Text('完成上方授权后，连接会显示在这里。'),
        ),
      );
    }
    return Column(
      children: [for (final grant in _grants) _grantCard(context, grant)],
    );
  }

  Widget _grantCard(BuildContext context, NationalFocusAiGrant grant) {
    final active = grant.isActiveAt(DateTime.now().toUtc());
    final status = active
        ? '已授权'
        : grant.revokedAt != null
        ? '已撤销'
        : '已过期';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  active ? Icons.verified_user_outlined : Icons.history,
                  semanticLabel: status,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text(grant.clientName), Text(status)],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('范围：${_scopeLabel(grant.scope)}'),
            Text('授权时间：${_formatDate(grant.createdAt)}'),
            Text('到期时间：${_formatDate(grant.expiresAt)}'),
            if (active) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _working ? null : () => _revokeGrant(grant),
                child: Text(_workingGrantId == grant.id ? '正在撤销…' : '撤销此连接'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _codexConfiguration(String mcpUrl) =>
      'codex mcp add $_serverName --url $mcpUrl\n'
      'codex mcp login $_serverName --oauth-client-registration dcr';

  static bool _isRequestCode(String value) =>
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);

  static Widget _sectionTitle(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );

  static String _scopeLabel(String scope) => switch (scope) {
    'national_focus:read' => '国策 AI 只读（当前仅开放云快照元数据）',
    _ => scope,
  };

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
