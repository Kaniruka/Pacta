import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/chain_signals_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

const _flow = String.fromEnvironment('ISSUE66_FLOW', defaultValue: 'none');
const _textScalePercent = int.fromEnvironment('ISSUE66_TEXT_SCALE');
const _userId = 'issue-66-manual-offline-fixture';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!const {'none', 'active', 'paused', 'appointment'}.contains(_flow)) {
    throw ArgumentError.value(
      _flow,
      'ISSUE66_FLOW',
      'Expected none, active, paused, or appointment.',
    );
  }

  final directory = await Directory.systemTemp.createTemp(
    'pacta-issue66-demo-',
  );
  final databaseFile = File(
    '${directory.path}${Platform.pathSeparator}issue66.sqlite',
  );
  final database = PactaDatabase(NativeDatabase(databaseFile));
  final taskRemote = InMemoryTaskRemote();
  final focusRemote = InMemoryFocusRemote();
  final tasks = LocalTaskRepository(
    database: database,
    userId: _userId,
    remote: taskRemote,
    cloudSyncEnabled: false,
  );
  final focus = LocalFocusRepository(
    database: database,
    userId: _userId,
    remote: focusRemote,
    cloudSyncEnabled: false,
  );
  final nationalFocus = LocalNationalFocusRepository(
    database: database,
    userId: _userId,
    cloudSyncEnabled: false,
  );
  final chainSignals = ChainSignalsRepository(
    database: database,
    userId: _userId,
  );

  final candidateGoal = await tasks.createGoal(
    const GoalDraft(
      title: 'Issue 66 候选任务（80）',
      classification: TaskClassification.both,
    ),
  );
  for (var index = 0; index < 80; index++) {
    final classification = switch (index) {
      0 => TaskClassification.regular,
      1 => TaskClassification.elite,
      2 => TaskClassification.both,
      _ when index % 3 == 0 => TaskClassification.regular,
      _ when index % 3 == 1 => TaskClassification.elite,
      _ => TaskClassification.both,
    };
    final modeLabel = switch (classification) {
      TaskClassification.regular => '普通',
      TaskClassification.elite => '精锐',
      TaskClassification.both => '两者',
    };
    final title = 'I66-${index.toString().padLeft(2, '0')}-$modeLabel';
    await tasks.createTask(
      candidateGoal.id,
      TaskDraft(
        title: title,
        classification: classification,
        estimatedMinutes: index == 1 ? 40 : null,
      ),
    );
  }

  if (_flow != 'none') {
    final originalGoal = await tasks.createGoal(
      const GoalDraft(
        title: 'Issue 66 原流程（恢复样例）',
        classification: TaskClassification.regular,
      ),
    );
    final originalTask = await tasks.createTask(
      originalGoal.id,
      const TaskDraft(
        title: 'Issue 66 原流程任务',
        classification: TaskClassification.regular,
      ),
    );
    switch (_flow) {
      case 'active':
        await focus.startSession(
          taskId: originalTask.id,
          mode: FocusChainMode.regular,
          duration: const Duration(minutes: 60),
        );
        await tasks.setTaskCompletion(originalTask.id, isComplete: true);
        break;
      case 'paused':
        final session = await focus.startSession(
          taskId: originalTask.id,
          mode: FocusChainMode.regular,
          duration: const Duration(minutes: 60),
        );
        await focus.pauseSession(session.id, ruleText: 'Issue 66 暂停恢复样例');
        await tasks.deleteGoal(originalGoal.id);
        break;
      case 'appointment':
        await focus.startAppointment(
          taskId: originalTask.id,
          mode: FocusChainMode.regular,
          duration: const Duration(minutes: 25),
        );
        await tasks.deleteGoal(originalGoal.id);
        break;
      case 'none':
        break;
    }
  }

  // ignore: avoid_print
  print('ISSUE66_DEMO_FLOW=$_flow');
  // ignore: avoid_print
  print('ISSUE66_DEMO_DATABASE=${databaseFile.path}');
  // ignore: avoid_print
  print('ISSUE66_DEMO_TEXT_SCALE=$_textScalePercent');

  runApp(
    _Issue66DemoHost(
      directory: directory,
      database: database,
      tasks: tasks,
      focus: focus,
      nationalFocus: nationalFocus,
      chainSignals: chainSignals,
      textScalePercent: _textScalePercent,
    ),
  );
}

class _Issue66DemoHost extends StatefulWidget {
  const _Issue66DemoHost({
    required this.directory,
    required this.database,
    required this.tasks,
    required this.focus,
    required this.nationalFocus,
    required this.chainSignals,
    required this.textScalePercent,
  });

  final Directory directory;
  final PactaDatabase database;
  final LocalTaskRepository tasks;
  final LocalFocusRepository focus;
  final LocalNationalFocusRepository nationalFocus;
  final ChainSignalsRepository chainSignals;
  final int textScalePercent;

  @override
  State<_Issue66DemoHost> createState() => _Issue66DemoHostState();
}

class _Issue66DemoHostState extends State<_Issue66DemoHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_closeFixture());
    super.dispose();
  }

  Future<void> _closeFixture() async {
    await widget.focus.dispose();
    await widget.tasks.dispose();
    await widget.nationalFocus.dispose();
    await widget.database.close();
    if (await widget.directory.exists()) {
      await widget.directory.delete(recursive: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewMedia = MediaQueryData.fromView(View.of(context));
    final media = widget.textScalePercent > 0
        ? viewMedia.copyWith(
            textScaler: TextScaler.linear(widget.textScalePercent / 100),
          )
        : viewMedia;
    return MediaQuery(
      data: media,
      child: PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _userId,
        focusNotificationService: DisabledFocusNotificationService(),
        taskRepositoryFactory: (_) => widget.tasks,
        focusRepositoryFactory: (_) => widget.focus,
        nationalFocusRepositoryFactory: (_) => widget.nationalFocus,
        chainSignalsRepositoryFactory: (_) => widget.chainSignals,
      ),
    );
  }
}
