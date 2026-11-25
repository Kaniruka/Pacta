import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试完整性机械守卫：把「用 ignore 压掉静态检查」与「用 skip 让测试假装
/// 通过」两类弱化，从评审口径变成每次 flutter test 都会执行的判定。
///
/// 判定只看 Dart 扫描器产出的注释 token 与语法树：字符串字面量里的注释示例
/// 不是注释，字符串里的调用示例不是调用，两类误报都不成立。全仓不变式扫描
/// lib、test、integration_test、test_driver，跳过生成代码与守卫自身。
void main() {
  group('守卫自身能识别违规且不误报字符串字面量', () {
    test('源码注释里的 ignore 与 ignore_for_file 按规则逐条列出', () {
      const source = '''
// ignore: directives_ordering

// ignore_for_file: avoid_print, unused_import
void main() {}
''';
      expect(
        _render(findDisallowedIgnores(source, allowedRules: const <String>{})),
        <String>[
          '1 ignore: directives_ordering',
          '3 ignore_for_file: avoid_print',
          '3 ignore_for_file: unused_import',
        ],
      );
    });

    test('lib 口径零容忍，测试口径放行的 avoid_print 也要拦下', () {
      const source = '''
void logIt() {
  // ignore: avoid_print
  print('debug');
}
''';
      expect(
        _render(findDisallowedIgnores(source, allowedRules: const <String>{})),
        <String>['2 ignore: avoid_print'],
      );
      expect(
        findDisallowedIgnores(
          source,
          allowedRules: const <String>{'avoid_print'},
        ),
        isEmpty,
      );
    });

    test('块注释、行尾注释与文件末尾（EOF 前）注释同样被检出', () {
      const source = '''
/* ignore: unused_local_variable */
int counter = 0;

void main() {
  final value = 1; // ignore: unnecessary_cast
  print(value);
}
// ignore: unused_element
''';
      expect(
        _render(findDisallowedIgnores(source, allowedRules: const <String>{})),
        <String>[
          '1 ignore: unused_local_variable',
          '5 ignore: unnecessary_cast',
          '8 ignore: unused_element',
        ],
      );
    });

    test('字符串字面量里的注释与 skip 示例不产生任何违规', () {
      const source = '''
const ignoreExample = '// ignore: directives_ordering';
const skipExample = 'test("x", () {}, skip: true)';
''';
      expect(
        findDisallowedIgnores(source, allowedRules: const <String>{}),
        isEmpty,
      );
      expect(
        findDisallowedTestSkips(
          source,
          allowedSkipExpressions: const <String>{},
        ),
        isEmpty,
      );
    });

    test('test / testWidgets / group / testGoldens 的非法 skip 全被检出', () {
      const source = '''
void main() {
  test('a', () {}, skip: true);
  testWidgets('b', (tester) async {}, skip: 'flaky');
  group('c', () {}, skip: 'todo');
  testGoldens('d', (tester) async {}, skip: false);
}
''';
      expect(
        _render(
          findDisallowedTestSkips(
            source,
            allowedSkipExpressions: const <String>{},
          ),
        ),
        <String>[
          '2 skip: true',
          "3 skip: 'flaky'",
          "4 skip: 'todo'",
          '5 skip: false',
        ],
      );
    });

    test('平台条件 skip 放行，同一处换成无条件 skip 立刻违规', () {
      const allowedSource = '''
void main() {
  test('a', () {}, skip: !Platform.isWindows);
}
''';
      const forbiddenSource = '''
void main() {
  test('a', () {}, skip: true);
}
''';
      const allowlist = <String>{'!Platform.isWindows'};
      expect(
        findDisallowedTestSkips(
          allowedSource,
          allowedSkipExpressions: allowlist,
        ),
        isEmpty,
      );
      expect(
        _render(
          findDisallowedTestSkips(
            forbiddenSource,
            allowedSkipExpressions: allowlist,
          ),
        ),
        <String>['2 skip: true'],
      );
    });

    test('测试目录只放行 avoid_print，其它规则与空规则都算违规', () {
      const allowedSource = '''
void main() {
  // ignore: avoid_print
  print('debug');
}
''';
      const mixedSource = '''
// ignore: avoid_print, unused_import
void main() {}
// ignore:
''';
      expect(
        findDisallowedIgnores(
          allowedSource,
          allowedRules: const <String>{'avoid_print'},
        ),
        isEmpty,
      );
      expect(
        _render(
          findDisallowedIgnores(
            mixedSource,
            allowedRules: const <String>{'avoid_print'},
          ),
        ),
        <String>['1 ignore: unused_import', '3 ignore: <empty>'],
      );
    });
  });

  group('全仓真实文件不变式', () {
    test('扫描集合来自真实源码，排除生成代码与守卫自身', () {
      final scanned = _dartFilesUnder(_scanRoots).map(_relativePath).toSet();
      expect(scanned, contains('lib/main.dart'));
      expect(scanned, contains('test/ui/ui_polish_guardrails_test.dart'));
      expect(
        scanned,
        contains('integration_test/ui_baseline_device_test.dart'),
      );
      expect(scanned, isNot(contains(_guardPath)));
      expect(scanned.where((path) => path.endsWith('.g.dart')), isEmpty);
      expect(scanned.length, greaterThan(300));
    });

    test('lib 目录零任何 ignore 压制', () {
      final violations = _ignoreViolations(
        _dartFilesUnder(const <String>['lib']),
        allowedRules: const <String>{},
      );
      expect(
        violations,
        isEmpty,
        reason:
            'lib 源码必须让静态检查真实通过，不能靠 // ignore 或 '
            '// ignore_for_file 压下去；放行只能改代码。违规：$violations',
      );
    });

    test('test / integration_test / test_driver 只允许 avoid_print', () {
      final violations = _ignoreViolations(
        _dartFilesUnder(const <String>[
          'test',
          'integration_test',
          'test_driver',
        ]),
        allowedRules: const <String>{'avoid_print'},
      );
      expect(
        violations,
        isEmpty,
        reason:
            '测试与平台验收代码只允许 // ignore: avoid_print 这一条设备日志豁免，'
            '其它 linter 压制一律算弱化测试。违规：$violations',
      );
    });

    test('test 目录 skip 只允许 !Platform.isWindows', () {
      final violations = _skipViolations(
        _dartFilesUnder(const <String>['test']),
        allowedSkipExpressions: const <String>{'!Platform.isWindows'},
      );
      expect(
        violations,
        isEmpty,
        reason:
            'skip 只允许按平台条件跳过（!Platform.isWindows），无条件或随手 '
            'skip 等于让测试假装通过。违规：$violations',
      );
    });
  });
}

/// 一条守卫违规：1-based 行号 + 违规文本（规则名或 skip 表达式源码）。
final class IntegrityViolation {
  const IntegrityViolation({required this.line, required this.detail});

  final int line;
  final String detail;

  @override
  String toString() => 'line $line: $detail';
}

/// 返回源码里被禁止的 // ignore: 与 // ignore_for_file: 压制。
///
/// 只认扫描器挂在 token 上的注释：字符串字面量里的同一段文字是字符串内容，
/// 不会出现在 [Token.precedingComments] 链上。[allowedRules] 是唯一放行的
/// linter 名集合，空集表示零容忍。
List<IntegrityViolation> findDisallowedIgnores(
  String content, {
  required Set<String> allowedRules,
}) {
  final result = parseString(content: content, throwIfDiagnostics: false);
  final violations = <IntegrityViolation>[];
  var token = result.unit.beginToken;
  while (true) {
    // 先扫当前 token 的注释再判断 EOF：文件末尾的注释挂在 EOF token 上，
    // 先 break 会漏掉它们。
    Token? comment = token.precedingComments;
    while (comment != null) {
      final directive = _ignoreDirective(comment.lexeme);
      if (directive != null) {
        final line = result.lineInfo.getLocation(comment.offset).lineNumber;
        for (final rule in directive.rules) {
          if (allowedRules.contains(rule)) continue;
          violations.add(
            IntegrityViolation(
              line: line,
              detail:
                  '${directive.keyword}: ${rule.isEmpty ? '<empty>' : rule}',
            ),
          );
        }
      }
      comment = comment.next;
    }
    if (token.isEof) break;
    final next = token.next;
    if (next == null || identical(next, token)) break;
    token = next;
  }
  return violations;
}

/// 返回测试 API 里不被允许的 skip: 表达式。
///
/// 命中 test、testWidgets、group、testGoldens 的命名参数 skip，
/// 表达式源码（去掉首尾空白）不在 [allowedSkipExpressions] 即算违规。
List<IntegrityViolation> findDisallowedTestSkips(
  String content, {
  required Set<String> allowedSkipExpressions,
}) {
  final result = parseString(content: content, throwIfDiagnostics: false);
  final visitor = _SkipVisitor(
    lineInfo: result.lineInfo,
    allowedSkipExpressions: allowedSkipExpressions,
  );
  result.unit.accept(visitor);
  return visitor.violations;
}

/// 全仓扫描根目录。
const List<String> _scanRoots = <String>[
  'lib',
  'test',
  'integration_test',
  'test_driver',
];

/// 守卫自身：内含正反例字面量，不参与全仓扫描。
const String _guardPath = 'test/quality/test_integrity_guardrails_test.dart';

/// ignore 指令本体：允许前导空白与块注释的星号前缀，冒号右侧是规则列表。
final RegExp _ignoreDirectivePattern = RegExp(
  r'^\s*(?:\*\s*)?ignore(_for_file)?\s*:(.*)$',
  dotAll: true,
);

/// 规则标识符：小写字母、数字与下划线，遇到空白、连字符或注释尾巴即止。
final RegExp _ruleIdentifierPattern = RegExp(r'^[a-z0-9_]+');

final class _IgnoreDirective {
  const _IgnoreDirective(this.keyword, this.rules);

  final String keyword;
  final List<String> rules;
}

_IgnoreDirective? _ignoreDirective(String commentLexeme) {
  final body = _commentBody(commentLexeme);
  if (body == null) return null;
  final match = _ignoreDirectivePattern.firstMatch(body);
  if (match == null) return null;
  final keyword = match.group(1) == null ? 'ignore' : 'ignore_for_file';
  final rules = match
      .group(2)!
      .split(',')
      .map((segment) => segment.trim())
      .map(
        (segment) =>
            _ruleIdentifierPattern.firstMatch(segment)?.group(0) ?? segment,
      )
      .toList(growable: false);
  return _IgnoreDirective(keyword, rules);
}

String? _commentBody(String lexeme) {
  if (lexeme.startsWith('//')) return lexeme.substring(2);
  if (lexeme.startsWith('/*') && lexeme.endsWith('*/')) {
    return lexeme.substring(2, lexeme.length - 2);
  }
  return null;
}

class _SkipVisitor extends RecursiveAstVisitor<void> {
  _SkipVisitor({required this.lineInfo, required this.allowedSkipExpressions});

  final LineInfo lineInfo;
  final Set<String> allowedSkipExpressions;
  final List<IntegrityViolation> violations = <IntegrityViolation>[];

  static const Set<String> _testApis = <String>{
    'group',
    'test',
    'testGoldens',
    'testWidgets',
  };

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_testApis.contains(node.methodName.name)) {
      for (final argument in node.argumentList.arguments) {
        if (argument is! NamedExpression) continue;
        if (argument.name.label.name != 'skip') continue;
        final expression = argument.expression.toSource().trim();
        if (allowedSkipExpressions.contains(expression)) continue;
        violations.add(
          IntegrityViolation(
            line: lineInfo.getLocation(argument.offset).lineNumber,
            detail: 'skip: $expression',
          ),
        );
      }
    }
    super.visitMethodInvocation(node);
  }
}

/// 扫描根下的 Dart 源文件：跳过生成代码（.g.dart）与守卫自身。
List<File> _dartFilesUnder(Iterable<String> roots) {
  final files = <File>[];
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = _relativePath(entity);
      if (!path.endsWith('.dart')) continue;
      if (path.endsWith('.g.dart') || path == _guardPath) continue;
      files.add(entity);
    }
  }
  return files;
}

String _relativePath(File file) => file.path.replaceAll('\\', '/');

List<String> _ignoreViolations(
  Iterable<File> files, {
  required Set<String> allowedRules,
}) => <String>[
  for (final file in files)
    for (final violation in findDisallowedIgnores(
      file.readAsStringSync(),
      allowedRules: allowedRules,
    ))
      '${_relativePath(file)}:${violation.line} ${violation.detail}',
];

List<String> _skipViolations(
  Iterable<File> files, {
  required Set<String> allowedSkipExpressions,
}) => <String>[
  for (final file in files)
    for (final violation in findDisallowedTestSkips(
      file.readAsStringSync(),
      allowedSkipExpressions: allowedSkipExpressions,
    ))
      '${_relativePath(file)}:${violation.line} ${violation.detail}',
];

List<String> _render(Iterable<IntegrityViolation> violations) => violations
    .map((violation) => '${violation.line} ${violation.detail}')
    .toList(growable: false);
