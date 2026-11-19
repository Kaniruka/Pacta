import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

const _sharedDisclosure = 'lib/src/ui/pacta_disclosure_section.dart';

List<int> _expansionTileOffsets(String source) {
  final visitor = _ExpansionTileVisitor();
  parseString(content: source).unit.accept(visitor);
  return visitor.offsets;
}

class _ExpansionTileVisitor extends RecursiveAstVisitor<void> {
  final offsets = <int>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'ExpansionTile') {
      offsets.add(node.offset);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Unresolved, non-const constructor calls can be parsed as invocations.
    if (node.methodName.name == 'ExpansionTile') offsets.add(node.offset);
    super.visitMethodInvocation(node);
  }
}

void main() {
  test('disclosure guard sees constructor calls, not comments or text', () {
    expect(
      _expansionTileOffsets('''
// ExpansionTile(title: Text('comment'))
final text = "ExpansionTile(title: Text('string'))";
final a = ExpansionTile(title: Text('a'));
final b = const ExpansionTile(title: Text('b'));
final c = material.ExpansionTile(title: Text('c'));
'''),
      hasLength(3),
    );
  });

  test('production disclosures use the shared styled section', () {
    expect(File(_sharedDisclosure).existsSync(), isTrue);
    final violations = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      final path = file.path.replaceAll('\\', '/');
      if (!path.endsWith('.dart') || path.endsWith('.g.dart')) continue;
      if (path == _sharedDisclosure) continue;
      final source = file.readAsStringSync();
      for (final offset in _expansionTileOffsets(source)) {
        final line = '\n'.allMatches(source.substring(0, offset)).length + 1;
        violations.add('$path:$line');
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Use PactaDisclosureSection ($_sharedDisclosure) so typography, '
          'borders and expanded-field padding are reviewed in one place.',
    );
  });
}
