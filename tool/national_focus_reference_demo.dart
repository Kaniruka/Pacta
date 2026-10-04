import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../test/support/national_focus_reference_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = PactaDatabase(NativeDatabase.memory());
  final repository = LocalNationalFocusRepository(
    database: database,
    userId: 'reference-image-demo-only',
    cloudSyncEnabled: false,
  );
  final fixture = await NationalFocusReferenceFixture.load();
  await fixture.seed(repository);

  runApp(
    _NationalFocusReferenceDemo(repository: repository, database: database),
  );
}

class _NationalFocusReferenceDemo extends StatefulWidget {
  const _NationalFocusReferenceDemo({
    required this.repository,
    required this.database,
  });

  final LocalNationalFocusRepository repository;
  final PactaDatabase database;

  @override
  State<_NationalFocusReferenceDemo> createState() =>
      _NationalFocusReferenceDemoState();
}

class _NationalFocusReferenceDemoState
    extends State<_NationalFocusReferenceDemo> {
  @override
  void dispose() {
    unawaited(_closeResources());
    super.dispose();
  }

  Future<void> _closeResources() async {
    await widget.repository.dispose();
    await widget.database.close();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '国策树图片样例预览',
    theme: ThemeData(colorSchemeSeed: const Color(0xff385a52)),
    darkTheme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xff385a52),
    ),
    home: Scaffold(
      appBar: AppBar(
        title: const Text('图片样例预览'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(38),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text('仅使用内存演示数据，不连接用户账户或云端', textAlign: TextAlign.center),
          ),
        ),
      ),
      body: SafeArea(
        child: NationalFocusTreePage(repository: widget.repository),
      ),
    ),
  );
}
