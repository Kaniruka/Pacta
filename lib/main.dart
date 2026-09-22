import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart' hide FocusNode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/auth/auth_repository.dart';
import 'src/auth/supabase_auth_repository.dart';
import 'src/focus/focus_models.dart';
import 'src/focus/focus_repository.dart';
import 'src/tasks/task_database.dart' show PactaDatabase;
import 'src/tasks/task_models.dart';
import 'src/tasks/task_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final url = const String.fromEnvironment('SUPABASE_URL');
  final key = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  AuthRepository repository = const UnavailableAuthRepository();
  final database = PactaDatabase.open();
  TaskRemoteDataSource remote = const UnavailableTaskRemoteDataSource();
  FocusRemoteDataSource focusRemote = const UnavailableFocusRemoteDataSource();
  if (url.isNotEmpty && key.isNotEmpty) {
    await Supabase.initialize(url: url, publishableKey: key);
    repository = SupabaseAuthRepository(Supabase.instance.client);
    remote = SupabaseTaskRemoteDataSource(Supabase.instance.client);
    focusRemote = SupabaseFocusRemoteDataSource(Supabase.instance.client);
  }
  runApp(
    PactaApp(
      authRepository: repository,
      taskRepositoryFactory: (userId) => LocalTaskRepository(
        database: database,
        userId: userId,
        remote: remote,
      ),
      focusRepositoryFactory: (userId) => LocalFocusRepository(
        database: database,
        userId: userId,
        remote: focusRemote,
      ),
    ),
  );
}

class PactaApp extends StatelessWidget {
  const PactaApp({
    super.key,
    required this.authRepository,
    this.taskRepositoryFactory,
    this.focusRepositoryFactory,
  });

  final AuthRepository authRepository;
  final TaskRepository Function(String userId)? taskRepositoryFactory;
  final FocusRepository Function(String userId)? focusRepositoryFactory;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepository),
        taskRepositoryFactoryProvider.overrideWithValue(
          taskRepositoryFactory ?? (_) => const UnavailableTaskRepository(),
        ),
        focusRepositoryFactoryProvider.overrideWithValue(
          focusRepositoryFactory ?? (_) => const UnavailableFocusRepository(),
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

final focusRepositoryFactoryProvider =
    Provider<FocusRepository Function(String userId)>((ref) {
      return (_) => const UnavailableFocusRepository();
    });

final taskRepositoryProvider = Provider.autoDispose<TaskRepository>((ref) {
  final userId = ref.watch(authRepositoryProvider).currentUserId;
  if (userId == null) return const UnavailableTaskRepository();
  final repository = ref.watch(taskRepositoryFactoryProvider)(userId);
  ref.onDispose(repository.dispose);
  return repository;
});

final focusRepositoryProvider = Provider.autoDispose<FocusRepository>((ref) {
  final userId = ref.watch(authRepositoryProvider).currentUserId;
  if (userId == null) return const UnavailableFocusRepository();
  final repository = ref.watch(focusRepositoryFactoryProvider)(userId);
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
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isRegistering = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || password.length < 8) {
      setState(() => _error = '请输入有效邮箱，以及至少 8 位密码。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(authRepositoryProvider);
      if (_isRegistering) {
        await repository.signUp(email: email, password: password);
      } else {
        await repository.signIn(email: email, password: password);
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
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: '邮箱'),
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
      await ref.read(focusRepositoryProvider).settleDueSessions();
      await ref.read(focusRepositoryProvider).sync();
    } catch (_) {
      // Focus records remain local and are retried on resume or reconnect.
    }
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

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.repository, required this.task});

  final TaskRepository repository;
  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deadline = task.deadline == null
        ? null
        : '截止 ${_formatDateTime(task.deadline!.toLocal())}';
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
          if (task.focusProgressSeconds > 0)
            '已专注 ${_formatDuration(task.focusProgressSeconds)}',
          ?deadline,
        ].join(' · '),
      ),
      trailing: IconButton(
        tooltip: '开始专注',
        onPressed: () async {
          final mode = await ref.read(focusRepositoryProvider).getLastMode();
          if (!context.mounted) return;
          final session = await showDialog<FocusSession>(
            context: context,
            builder: (_) => FocusSetupDialog(task: task, initialMode: mode),
          );
          if (session != null && context.mounted) {
            var taskTitle = task.title;
            if (session.taskId != task.id) {
              final goals = await repository.getGoals();
              if (!context.mounted) return;
              taskTitle = _findTaskTitle(goals, session.taskId) ?? '原任务';
            }
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    FocusSessionPage(session: session, taskTitle: taskTitle),
              ),
            );
          }
        },
        icon: const Icon(Icons.play_arrow_rounded),
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
    _deadline = widget.initial?.deadline?.toLocal();
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

String _formatDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;
  return '$minutes分${remainingSeconds.toString().padLeft(2, '0')}秒';
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

class FocusChainPage extends ConsumerStatefulWidget {
  const FocusChainPage({super.key});

  @override
  ConsumerState<FocusChainPage> createState() => _FocusChainPageState();
}

class _FocusChainPageState extends ConsumerState<FocusChainPage> {
  TaskClassification? _filter;
  FocusChainMode _lastMode = FocusChainMode.regular;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLastMode());
  }

  Future<void> _loadLastMode() async {
    final mode = await ref.read(focusRepositoryProvider).getLastMode();
    if (mounted) setState(() => _lastMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final taskRepository = ref.watch(taskRepositoryProvider);
    final focusRepository = ref.watch(focusRepositoryProvider);
    return StreamBuilder<List<Goal>>(
      stream: taskRepository.watchGoals(),
      initialData: const [],
      builder: (context, snapshot) {
        final taskTitles = <String, String>{
          for (final goal in snapshot.data ?? const <Goal>[])
            for (final task in goal.tasks) task.id: task.title,
        };
        final tasks = [
          for (final goal in snapshot.data ?? const <Goal>[])
            for (final task in goal.tasks)
              if (!task.isComplete && _matchesFilter(task)) task,
        ];
        return StreamBuilder<List<FocusSession>>(
          stream: focusRepository.watchSessions(),
          initialData: const [],
          builder: (context, sessionsSnapshot) {
            final sessions = sessionsSnapshot.data ?? const <FocusSession>[];
            final active = sessions
                .where((session) => session.isUnfinished)
                .firstOrNull;
            final activeTask = active == null
                ? null
                : tasks.where((task) => task.id == active.taskId).firstOrNull;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
              children: [
                Text('专注链', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                const Text('选择一个未完成任务，设定本次模式和时长。'),
                if (active != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: const Text('已有进行中的专注'),
                      subtitle: Text(activeTask?.title ?? '原任务'),
                      trailing: FilledButton(
                        onPressed: () =>
                            _openSession(active, activeTask?.title ?? '原任务'),
                        child: const Text('返回专注'),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SegmentedButton<TaskClassification?>(
                  segments: const [
                    ButtonSegment<TaskClassification?>(
                      value: null,
                      label: Text('全部'),
                    ),
                    ButtonSegment<TaskClassification?>(
                      value: TaskClassification.elite,
                      label: Text('精锐'),
                    ),
                    ButtonSegment<TaskClassification?>(
                      value: TaskClassification.regular,
                      label: Text('普通'),
                    ),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (values) =>
                      setState(() => _filter = values.single),
                ),
                const SizedBox(height: 12),
                if (tasks.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('当前筛选下没有可开始的任务。'),
                    ),
                  )
                else
                  for (final task in tasks)
                    Card(
                      child: ListTile(
                        title: Text(task.title),
                        subtitle: Text(
                          '${task.classification.label} · 已专注 '
                          '${_formatDuration(task.focusProgressSeconds)}',
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () => _showSetup(task),
                          child: const Text('开始'),
                        ),
                      ),
                    ),
                const SizedBox(height: 16),
                FutureBuilder<List<FocusChainRecord>>(
                  future: focusRepository.getChainRecords(),
                  builder: (context, recordSnapshot) {
                    final records = recordSnapshot.data ?? const [];
                    if (records.isEmpty) return const SizedBox.shrink();
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '连续记录',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            for (final record in records)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(record.mode.label),
                                trailing: Text(
                                  '${record.currentConsecutive} 次 · 最佳 ${record.bestConsecutive} 次',
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                if (sessions.any((session) => !session.isUnfinished))
                  FutureBuilder<List<FocusNode>>(
                    future: focusRepository.getNodes(),
                    builder: (context, nodeSnapshot) => _FocusHistoryCard(
                      repository: focusRepository,
                      sessions: sessions
                          .where((session) => !session.isUnfinished)
                          .toList(),
                      nodes: nodeSnapshot.data ?? const [],
                      taskTitles: taskTitles,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  bool _matchesFilter(Task task) {
    return switch (_filter) {
      null => true,
      TaskClassification.elite =>
        task.classification == TaskClassification.elite ||
            task.classification == TaskClassification.both,
      TaskClassification.regular =>
        task.classification == TaskClassification.regular ||
            task.classification == TaskClassification.both,
      TaskClassification.both => true,
    };
  }

  FocusChainMode get _selectedMode => switch (_filter) {
    TaskClassification.elite => FocusChainMode.elite,
    TaskClassification.regular => FocusChainMode.regular,
    _ => _lastMode,
  };

  Future<void> _showSetup(Task task) async {
    final session = await showDialog<FocusSession>(
      context: context,
      builder: (_) => FocusSetupDialog(task: task, initialMode: _selectedMode),
    );
    if (session != null && mounted) {
      final goals = await ref.read(taskRepositoryProvider).getGoals();
      _openSession(
        session,
        _findTaskTitle(goals, session.taskId) ?? task.title,
      );
    }
    if (session != null) {
      setState(() => _lastMode = session.mode);
    }
  }

  void _openSession(FocusSession session, String taskTitle) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FocusSessionPage(session: session, taskTitle: taskTitle),
      ),
    );
  }
}

String? _findTaskTitle(List<Goal> goals, String taskId) {
  for (final goal in goals) {
    for (final task in goal.tasks) {
      if (task.id == taskId) return task.title;
    }
  }
  return null;
}

class _FocusHistoryCard extends StatelessWidget {
  const _FocusHistoryCard({
    required this.repository,
    required this.sessions,
    required this.nodes,
    required this.taskTitles,
  });

  final FocusRepository repository;
  final List<FocusSession> sessions;
  final List<FocusNode> nodes;
  final Map<String, String> taskTitles;

  @override
  Widget build(BuildContext context) {
    final nodesBySession = {for (final node in nodes) node.sessionId: node};
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('专注历史', style: Theme.of(context).textTheme.titleMedium),
            for (final session in sessions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(taskTitles[session.taskId] ?? '原任务'),
                subtitle: Text(
                  session.isFailed
                      ? '失败 · ${_formatDuration(session.effectiveSeconds)}\n原因：${session.failureReason ?? '未填写'}'
                      : '正常完成 · ${_formatDuration(session.effectiveSeconds)}',
                ),
                trailing: Wrap(
                  children: [
                    if (session.isFailed)
                      IconButton(
                        tooltip: '编辑失败原因',
                        icon: const Icon(Icons.edit_note_outlined),
                        onPressed: () async {
                          final reason = await _showTextEditor(
                            context,
                            title: '编辑失败原因',
                            label: '失败原因',
                            initial: session.failureReason ?? '',
                            required: true,
                          );
                          if (reason != null) {
                            await repository.updateFailureReason(
                              sessionId: session.id,
                              failureReason: reason,
                            );
                          }
                        },
                      ),
                    if (nodesBySession[session.id] case final node?)
                      IconButton(
                        tooltip: '编辑节点备注',
                        icon: const Icon(Icons.sticky_note_2_outlined),
                        onPressed: () async {
                          final note = await _showTextEditor(
                            context,
                            title: '编辑节点备注',
                            label: '备注（可选）',
                            initial: node.note ?? '',
                          );
                          if (note != null) {
                            await repository.updateNodeNote(
                              nodeId: node.id,
                              note: note,
                            );
                          }
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _showTextEditor(
  BuildContext context, {
  required String title,
  required String label,
  required String initial,
  bool required = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextEditorDialog(
      title: title,
      label: label,
      initial: initial,
      required: required,
    ),
  );
}

class _TextEditorDialog extends StatefulWidget {
  const _TextEditorDialog({
    required this.title,
    required this.label,
    required this.initial,
    this.required = false,
  });

  final String title;
  final String label;
  final String initial;
  final bool required;

  @override
  State<_TextEditorDialog> createState() => _TextEditorDialogState();
}

class _TextEditorDialogState extends State<_TextEditorDialog> {
  late final TextEditingController _text;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final value = _text.text.trim();
    if (widget.required && value.isEmpty) {
      setState(() => _error = '请填写${widget.label}。');
      return;
    }
    if (value.length > 500) {
      setState(() => _error = '内容不能超过 500 字。');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _text,
      autofocus: true,
      maxLines: 4,
      maxLength: 500,
      decoration: InputDecoration(labelText: widget.label, errorText: _error),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );
}

class FocusSetupDialog extends ConsumerStatefulWidget {
  const FocusSetupDialog({
    super.key,
    required this.task,
    required this.initialMode,
  });

  final Task task;
  final FocusChainMode initialMode;

  @override
  ConsumerState<FocusSetupDialog> createState() => _FocusSetupDialogState();
}

class _FocusSetupDialogState extends ConsumerState<FocusSetupDialog> {
  late FocusChainMode _mode;
  late final TextEditingController _duration;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _duration = TextEditingController(text: '25');
  }

  @override
  void dispose() {
    _duration.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final minutes = int.tryParse(_duration.text.trim());
    if (minutes == null || minutes <= 0) {
      setState(() => _error = '请输入大于 0 的分钟数。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await ref
          .read(focusRepositoryProvider)
          .startSession(
            taskId: widget.task.id,
            mode: _mode,
            duration: Duration(minutes: minutes),
          );
      if (mounted) Navigator.of(context).pop(session);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('开始专注'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.task.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        DropdownButtonFormField<FocusChainMode>(
          initialValue: _mode,
          decoration: const InputDecoration(labelText: '本次专注模式'),
          items: [
            for (final mode in FocusChainMode.values)
              DropdownMenuItem(value: mode, child: Text(mode.label)),
          ],
          onChanged: _busy ? null : (value) => setState(() => _mode = value!),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _duration,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '时长（分钟）'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 10),
        const Text('启动信号由你执行，App 不检测现实动作。倒计时归零后自动结算。'),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _busy ? null : _start,
        child: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('开始倒计时'),
      ),
    ],
  );
}

class FocusSessionPage extends ConsumerStatefulWidget {
  const FocusSessionPage({
    super.key,
    required this.session,
    required this.taskTitle,
  });

  final FocusSession session;
  final String taskTitle;

  @override
  ConsumerState<FocusSessionPage> createState() => _FocusSessionPageState();
}

class _FocusSessionPageState extends ConsumerState<FocusSessionPage> {
  Timer? _timer;
  FocusSession? _current;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _current = widget.session;
    _refresh();
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _refresh(),
    );
  }

  Future<void> _refresh() async {
    final session = await ref
        .read(focusRepositoryProvider)
        .getSession(widget.session.id);
    if (!mounted) return;
    if (session != null) setState(() => _current = session);
  }

  Future<void> _togglePause() async {
    final session = _current;
    if (session == null || _busy) return;
    String? ruleText;
    if (!session.isPaused) {
      ruleText = await _showTextEditor(
        context,
        title: '暂停本次专注',
        label: '下必为例',
        initial: '',
        required: true,
      );
      if (ruleText == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final repository = ref.read(focusRepositoryProvider);
      _current = session.isPaused
          ? await repository.resumeSession(session.id)
          : await repository.pauseSession(session.id, ruleText: ruleText!);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _abandon() async {
    final session = _current;
    if (session == null || !session.isUnfinished || _busy) return;
    final reason = await _showTextEditor(
      context,
      title: '放弃本次专注',
      label: '失败原因',
      initial: '',
      required: true,
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      _current = await ref
          .read(focusRepositoryProvider)
          .abandonSession(sessionId: session.id, failureReason: reason);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _current ?? widget.session;
    final now = DateTime.now().toUtc();
    final reference = session.isPaused ? (session.pausedAt ?? now) : now;
    final remaining = session.endsAt.difference(reference);
    final remainingSeconds = remaining.inSeconds.clamp(
      0,
      session.durationSeconds,
    );
    final progress = session.durationSeconds == 0
        ? 1.0
        : 1 - (remainingSeconds / session.durationSeconds);
    final settled = !session.isUnfinished;
    return Scaffold(
      appBar: AppBar(title: const Text('专注进行中')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.taskTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(session.mode.label, textAlign: TextAlign.center),
                const SizedBox(height: 36),
                Text(
                  settled ? '00:00' : _formatClock(remainingSeconds),
                  style: Theme.of(context).textTheme.displayLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                LinearProgressIndicator(value: settled ? 1 : progress),
                const SizedBox(height: 20),
                Text(
                  session.isFailed
                      ? '本次专注已失败，已保留有效投入时间。任务仍需你单独确认完成。\n失败原因：${session.failureReason ?? '未填写'}'
                      : session.status == FocusSessionStatus.completed
                      ? '本次专注已完成，已生成一个专注节点并记录有效时间。任务仍需你单独确认完成。'
                      : session.isPaused
                      ? '本次专注已暂停，暂停时间不计入有效投入。'
                      : '倒计时归零后自动结算。返回其他页面不会使本次专注失败。',
                  textAlign: TextAlign.center,
                ),
                if (session.isUnfinished) ...[
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _togglePause,
                        icon: Icon(
                          session.isPaused ? Icons.play_arrow : Icons.pause,
                        ),
                        label: Text(session.isPaused ? '继续' : '暂停'),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: _busy ? null : _abandon,
                        child: const Text('放弃本次专注'),
                      ),
                    ],
                  ),
                ],
                if (settled) ...[
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('返回专注链'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatClock(int seconds) {
  final minutes = seconds ~/ 60;
  final remaining = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}';
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
  final _email = TextEditingController();
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _grant() async {
    await _run(
      () => ref
          .read(authRepositoryProvider)
          .grantEligibility(email: _email.text.trim()),
      '资格已发放',
    );
  }

  Future<void> _revoke() async {
    await _run(() async {
      final changed = await ref
          .read(authRepositoryProvider)
          .revokeEligibility(email: _email.text.trim());
      if (!changed) throw StateError('资格不存在、已使用或已被撤销。');
    }, '资格已撤销');
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _message = '请输入有效的邮箱地址。');
      return;
    }
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
                  controller: _email,
                  decoration: const InputDecoration(labelText: '邮箱'),
                ),
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
