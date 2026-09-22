import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/auth/auth_repository.dart';
import 'src/auth/supabase_auth_repository.dart';
import 'src/tasks/task_database.dart';
import 'src/tasks/task_models.dart';
import 'src/tasks/task_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final url = const String.fromEnvironment('SUPABASE_URL');
  final key = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  AuthRepository repository = const UnavailableAuthRepository();
  final database = PactaDatabase.open();
  TaskRemoteDataSource remote = const UnavailableTaskRemoteDataSource();
  if (url.isNotEmpty && key.isNotEmpty) {
    await Supabase.initialize(url: url, publishableKey: key);
    repository = SupabaseAuthRepository(Supabase.instance.client);
    remote = SupabaseTaskRemoteDataSource(Supabase.instance.client);
  }
  runApp(
    PactaApp(
      authRepository: repository,
      taskRepositoryFactory: (userId) => LocalTaskRepository(
        database: database,
        userId: userId,
        remote: remote,
      ),
    ),
  );
}

class PactaApp extends StatelessWidget {
  const PactaApp({
    super.key,
    required this.authRepository,
    this.taskRepositoryFactory,
  });

  final AuthRepository authRepository;
  final TaskRepository Function(String userId)? taskRepositoryFactory;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepository),
        taskRepositoryFactoryProvider.overrideWithValue(
          taskRepositoryFactory ?? (_) => const UnavailableTaskRepository(),
        ),
      ],
      child: MaterialApp(
        title: 'Pacta',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff385a52),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xfff8faf8),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: const AuthGate(),
      ),
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return const UnavailableAuthRepository();
});

final taskRepositoryFactoryProvider =
    Provider<TaskRepository Function(String userId)>((ref) {
      return (_) => const UnavailableTaskRepository();
    });

final taskRepositoryProvider = Provider.autoDispose<TaskRepository>((ref) {
  final userId = ref.watch(authRepositoryProvider).currentUserId;
  if (userId == null) return const UnavailableTaskRepository();
  final repository = ref.watch(taskRepositoryFactoryProvider)(userId);
  ref.onDispose(repository.dispose);
  return repository;
});

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(authRepositoryProvider);
    return StreamBuilder<String?>(
      stream: repository.authState,
      initialData: repository.currentUserIdentifier,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data == null ? const AuthScreen() : const AppShell();
      },
    );
  }
}

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _isRegistering = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final identifier = _identifier.text.trim();
    final password = _password.text;
    if (identifier.isEmpty || password.length < 8) {
      setState(() => _error = '请输入邮箱或手机号，以及至少 8 位密码。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(authRepositoryProvider);
      if (_isRegistering) {
        await repository.signUp(identifier: identifier, password: password);
      } else {
        await repository.signIn(identifier: identifier, password: password);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object error) {
    if (error is AuthException) {
      if (error.message.toLowerCase().contains('eligib')) {
        return '该标识没有可用的注册资格，请联系管理员。';
      }
      return error.message;
    }
    return error.toString().replaceFirst('Bad state: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.anchor_rounded, size: 48, color: colors.primary),
                    const SizedBox(height: 16),
                    Text(
                      '进入 Pacta',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRegistering ? '使用管理员发放的资格创建你的访问凭据。' : '把注意力带回眼前的一步。',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _identifier,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: '邮箱或手机号'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '密码'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: TextStyle(color: colors.error)),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isRegistering ? '注册' : '登录'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _isRegistering = !_isRegistering;
                              _error = null;
                            }),
                      child: Text(
                        _isRegistering ? '已有账号？返回登录' : '还没有资格？请联系管理员发放注册资格',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int _index = 0;
  late final StreamSubscription<List<ConnectivityResult>>
  _connectivitySubscription;

  static const _destinations = [
    _Destination('看板', Icons.dashboard_outlined, Icons.dashboard),
    _Destination('国策树', Icons.account_tree_outlined, Icons.account_tree),
    _Destination('专注链', Icons.bolt_outlined, Icons.bolt),
    _Destination('我的', Icons.person_outline, Icons.person),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      _,
    ) {
      unawaited(_syncTasks());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncTasks());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_syncTasks());
  }

  Future<void> _syncTasks() async {
    try {
      await ref.read(taskRepositoryProvider).sync();
    } catch (_) {
      // Offline edits stay local and are retried on resume or reconnect.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const BoardPage(),
      const NationalFocusPage(),
      const FocusChainPage(),
      const MyPage(),
    ];
    final destination = _destinations[_index];
    return Scaffold(
      appBar: AppBar(title: Text(destination.label)),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          for (final item in _destinations)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class BoardPage extends ConsumerWidget {
  const BoardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(taskRepositoryProvider);
    return StreamBuilder<List<Goal>>(
      stream: repository.watchGoals(),
      initialData: const [],
      builder: (context, snapshot) {
        final goals = snapshot.data ?? const <Goal>[];
        return _BoardContent(repository: repository, goals: goals);
      },
    );
  }
}

class _BoardContent extends StatelessWidget {
  const _BoardContent({required this.repository, required this.goals});

  final TaskRepository repository;
  final List<Goal> goals;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '今天先做什么',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            FilledButton.icon(
              onPressed: () => _createGoal(context),
              icon: const Icon(Icons.add),
              label: const Text('新建目标'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (goals.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 48),
                  SizedBox(height: 12),
                  Text('暂无任务', style: TextStyle(fontSize: 22)),
                  SizedBox(height: 8),
                  Text('创建目标和任务后，它们会优先出现在这里。'),
                ],
              ),
            ),
          )
        else
          for (final goal in goals)
            _GoalCard(repository: repository, goal: goal),
      ],
    );
  }

  Future<void> _createGoal(BuildContext context) async {
    final draft = await _showGoalDialog(context);
    if (draft != null) await repository.createGoal(draft);
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.repository, required this.goal});

  final TaskRepository repository;
  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final status = goal.tasks.isEmpty
        ? '暂无任务 · 未完成'
        : goal.isComplete
        ? '已完成'
        : '进行中';
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(goal.title),
              subtitle: Text('${goal.classification.label} · $status'),
              trailing: IconButton(
                tooltip: '编辑目标',
                onPressed: () async {
                  final draft = await _showGoalDialog(context, initial: goal);
                  if (draft != null) {
                    await repository.updateGoal(goal.id, draft);
                  }
                },
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
            if (goal.tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('暂无任务，先添加一个可执行的下一步。'),
              )
            else
              for (final task in goal.tasks)
                _TaskTile(repository: repository, task: task),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final draft = await _showTaskDialog(context, goal: goal);
                  if (draft != null) {
                    await repository.createTask(goal.id, draft);
                  }
                },
                icon: const Icon(Icons.add_task),
                label: const Text('添加任务'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.repository, required this.task});

  final TaskRepository repository;
  final Task task;

  @override
  Widget build(BuildContext context) {
    final deadline = task.deadline == null
        ? null
        : '截止 ${_formatDateTime(task.deadline!)}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        value: task.isComplete,
        onChanged: (value) {
          if (value != null) {
            repository.setTaskCompletion(task.id, isComplete: value);
          }
        },
      ),
      title: Text(
        task.title,
        style: task.isComplete
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text(
        [
          task.classification.label,
          if (task.estimatedMinutes != null) '${task.estimatedMinutes} 分钟',
          ?deadline,
        ].join(' · '),
      ),
      onTap: () async {
        final draft = await _showTaskDialog(context, task: task);
        if (draft != null) await repository.updateTask(task.id, draft);
      },
    );
  }
}

Future<GoalDraft?> _showGoalDialog(BuildContext context, {Goal? initial}) {
  return showDialog<GoalDraft>(
    context: context,
    builder: (_) => _GoalDialog(initial: initial),
  );
}

Future<TaskDraft?> _showTaskDialog(
  BuildContext context, {
  Goal? goal,
  Task? task,
}) {
  return showDialog<TaskDraft>(
    context: context,
    builder: (_) => _TaskDialog(goal: goal, initial: task),
  );
}

class _GoalDialog extends StatefulWidget {
  const _GoalDialog({this.initial});

  final Goal? initial;

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late final TextEditingController _title;
  late TaskClassification _classification;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial?.title);
    _classification =
        widget.initial?.classification ?? TaskClassification.regular;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? '新建目标' : '编辑目标'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _title,
          autofocus: true,
          decoration: const InputDecoration(labelText: '目标名称'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<TaskClassification>(
          initialValue: _classification,
          decoration: const InputDecoration(labelText: '新任务默认分类'),
          items: [
            for (final classification in TaskClassification.values)
              DropdownMenuItem(
                value: classification,
                child: Text(classification.label),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _classification = value);
          },
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          GoalDraft(title: _title.text, classification: _classification),
        ),
        child: const Text('保存'),
      ),
    ],
  );
}

class _TaskDialog extends StatefulWidget {
  const _TaskDialog({this.goal, this.initial});

  final Goal? goal;
  final Task? initial;

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  late final TextEditingController _title;
  late final TextEditingController _estimatedMinutes;
  late TaskClassification _classification;
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial?.title);
    _estimatedMinutes = TextEditingController(
      text: widget.initial?.estimatedMinutes?.toString(),
    );
    _classification =
        widget.initial?.classification ??
        widget.goal?.classification ??
        TaskClassification.regular;
    _deadline = widget.initial?.deadline;
  }

  @override
  void dispose() {
    _title.dispose();
    _estimatedMinutes.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final initialDate = _deadline ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: initialDate,
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deadline ?? DateTime.now()),
    );
    if (!mounted || time == null) return;
    setState(
      () => _deadline = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? '新建任务' : '编辑任务'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: '任务名称'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<TaskClassification>(
            initialValue: _classification,
            decoration: const InputDecoration(labelText: '任务分类'),
            items: [
              for (final classification in TaskClassification.values)
                DropdownMenuItem(
                  value: classification,
                  child: Text(classification.label),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _classification = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _estimatedMinutes,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '预计时长（分钟，可选）'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _deadline == null
                      ? '未设置截止时间'
                      : '截止 ${_formatDateTime(_deadline!)}',
                ),
              ),
              IconButton(
                tooltip: '设置截止时间',
                onPressed: _pickDeadline,
                icon: const Icon(Icons.event_outlined),
              ),
              if (_deadline != null)
                IconButton(
                  tooltip: '清除截止时间',
                  onPressed: () => setState(() => _deadline = null),
                  icon: const Icon(Icons.clear),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          TaskDraft(
            title: _title.text,
            classification: _classification,
            estimatedMinutes: int.tryParse(_estimatedMinutes.text.trim()),
            deadline: _deadline,
          ),
        ),
        child: const Text('保存'),
      ),
    ],
  );
}

String _formatDateTime(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

class NationalFocusPage extends StatelessWidget {
  const NationalFocusPage({super.key});

  @override
  Widget build(BuildContext context) => const _EmptyPage(
    title: '国策树',
    message: '国策树还是空的',
    detail: '你的国策卡会在这里形成结构。它们由你手动维护和确认。',
    icon: Icons.account_tree_outlined,
  );
}

class FocusChainPage extends StatelessWidget {
  const FocusChainPage({super.key});

  @override
  Widget build(BuildContext context) => const _EmptyPage(
    title: '专注链',
    message: '从任务开始一次专注',
    detail: '选择任务后，可以设置本次模式和时长。当前没有可选择的任务。',
    icon: Icons.bolt_outlined,
  );
}

class MyPage extends ConsumerWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(authRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(repository.currentUserIdentifier ?? '当前用户'),
            subtitle: const Text('个人数据仅属于你'),
          ),
        ),
        FutureBuilder<bool>(
          future: repository.isAdministrator(),
          builder: (context, snapshot) => snapshot.data == true
              ? const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: AdminEligibilityCard(),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('设置'),
            subtitle: const Text('通知、显示与设备偏好将在这里管理'),
            onTap: () {},
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => ref.read(authRepositoryProvider).signOut(),
          icon: const Icon(Icons.logout),
          label: const Text('退出登录'),
        ),
      ],
    );
  }
}

class AdminEligibilityCard extends ConsumerStatefulWidget {
  const AdminEligibilityCard({super.key});

  @override
  ConsumerState<AdminEligibilityCard> createState() =>
      _AdminEligibilityCardState();
}

class _AdminEligibilityCardState extends ConsumerState<AdminEligibilityCard> {
  final _identifier = TextEditingController();
  String _type = 'email';
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _identifier.dispose();
    super.dispose();
  }

  Future<void> _grant() async {
    await _run(
      () => ref
          .read(authRepositoryProvider)
          .grantEligibility(identifier: _identifier.text.trim(), type: _type),
      '资格已发放',
    );
  }

  Future<void> _revoke() async {
    await _run(() async {
      final changed = await ref
          .read(authRepositoryProvider)
          .revokeEligibility(identifier: _identifier.text.trim(), type: _type);
      if (!changed) throw StateError('资格不存在、已使用或已被撤销。');
    }, '资格已撤销');
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_identifier.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (mounted) {
        setState(() => _message = success);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('管理员：注册资格', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('资格不发送消息，也不验证标识所有权。'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _identifier,
                  decoration: const InputDecoration(labelText: '邮箱或手机号'),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _type,
                items: const [
                  DropdownMenuItem(value: 'email', child: Text('邮箱')),
                  DropdownMenuItem(value: 'phone', child: Text('手机号')),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _type = value!),
              ),
            ],
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_message!),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _grant,
                  child: const Text('发放资格'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _revoke,
                  child: const Text('撤销未用资格'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _EmptyPage extends StatelessWidget {
  const _EmptyPage({
    required this.title,
    required this.message,
    required this.detail,
    required this.icon,
  });

  final String title;
  final String message;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 20),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(detail, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
