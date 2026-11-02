import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

// Conservative proxy for English: count visible literals containing Latin
// words, including interpolated and conditional literals. Brand names also
// count. The baseline permits existing debt, never growth in another file.
class _Strings extends RecursiveAstVisitor<void> {
  final offsets = <int>{};
  void record(StringLiteral node) {
    if (RegExp(r'[A-Za-z]{2}').hasMatch(node.toSource())) {
      offsets.add(node.offset);
    }
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => record(node);
  @override
  void visitStringInterpolation(StringInterpolation node) {
    // Examine visible segments, not string keys inside interpolation code.
    if (node.elements.whereType<InterpolationString>().any(
      (part) => RegExp(r'[A-Za-z]{2}').hasMatch(part.value),
    )) {
      offsets.add(node.offset);
    }
  }
}

class _VisibleArguments extends RecursiveAstVisitor<void> {
  final strings = _Strings();
  @override
  void visitArgumentList(ArgumentList node) {
    final prefix = node.parent!.toSource().split('(').first;
    final isText = RegExp(r'\bText$').hasMatch(prefix);
    final isSnackBar = RegExp(r'\bSnackBar$').hasMatch(prefix);
    for (final argument in node.arguments) {
      if (argument is NamedArgument) {
        final name = argument.name.lexeme;
        if (const {'labelText', 'hintText', 'tooltip'}.contains(name) ||
            (isSnackBar && name == 'content')) {
          argument.argumentExpression.accept(strings);
        }
      } else if (isText && argument == node.arguments.first) {
        argument.accept(strings);
      }
    }
    super.visitArgumentList(node);
  }
}

int _count(String source) {
  final visitor = _VisibleArguments();
  parseString(content: source, throwIfDiagnostics: false).unit.accept(visitor);
  return visitor.strings.offsets.length;
}

// Audit baseline, 2026-10-31. Decreases are welcome. Do not regenerate this
// map to accommodate new literals: localize them instead.
const _baseline = <String, int>{
  'lib/desktop/chat_pane.dart': 3,
  'lib/desktop/compare_page.dart': 2,
  'lib/desktop/hf_discover.dart': 3,
  'lib/desktop/image_gen_page.dart': 9,
  'lib/desktop/model_tune_section.dart': 3,
  'lib/desktop/projects_page.dart': 2,
  'lib/desktop/settings_panel.dart': 1,
  'lib/desktop/sidebar.dart': 2,
  'lib/desktop/title_bar.dart': 1,
  'lib/features/chat/presentation/screens/context_inspector_page.dart': 8,
  'lib/features/chat/presentation/screens/conversation_workspace_page.dart': 3,
  'lib/features/chat/presentation/widgets/chat_bubble.dart': 29,
  'lib/features/chat/presentation/widgets/code_block.dart': 1,
  'lib/features/models/presentation/screens/hf_search_page.dart': 1,
  'lib/features/models/presentation/screens/models_screen.dart': 1,
  'lib/features/onboarding/presentation/widgets/onboarding_steps.dart': 2,
  'lib/features/presets/presentation/preset_sheet.dart': 2,
  'lib/features/settings/presentation/screens/advanced_pages.dart': 1,
  'lib/features/settings/presentation/screens/advanced_sampling_page.dart': 3,
  'lib/features/settings/presentation/screens/advanced_tools_page.dart': 4,
  'lib/features/settings/presentation/screens/effective_settings_page.dart': 5,
  'lib/features/settings/presentation/screens/knowledge_page.dart': 1,
  'lib/features/settings/presentation/screens/remote_profile_page.dart': 3,
  'lib/features/settings/presentation/screens/scan_settings_page.dart': 3,
  'lib/features/settings/presentation/screens/settings_screen.dart': 3,
  'lib/features/settings/presentation/widgets/metrics_sheet.dart': 1,
  'lib/features/settings/presentation/widgets/settings_widgets.dart': 2,
  'lib/features/shortcuts/presentation/shortcuts_page.dart': 1,
  'lib/features/tools/presentation/tools_quick_panel.dart': 4,
};

void main() {
  test(
    'scanner covers visible slots without comments or interpolation keys',
    () {
      expect(
        _count(r'''
      void f() {
        Text('Hello');
        const Text("Welcome");
        Text(flag ? 'Yes' : 'No');
        Text('Loaded $count models');
        Text('${data['internal_key']}');
        InputDecoration(labelText: 'Name', hintText: "Enter name");
        IconButton(tooltip: 'Open');
        SnackBar(content: Text('Saved'));
        // Text('Comment');
        Text(l10n.title);
        final internal = 'Not visible';
      }
    '''),
        9,
      );
    },
  );

  test(
    'visible English literal counts do not grow beyond each file baseline',
    () {
      final files =
          Directory('lib').listSync(recursive: true).whereType<File>().where((
            file,
          ) {
            final path = file.path.replaceAll('\\', '/');
            return RegExp(r'^lib/desktop/[^/]+\.dart$').hasMatch(path) ||
                RegExp(
                  r'^lib/features/.+/presentation/.+\.dart$',
                ).hasMatch(path);
          }).toList()..sort((a, b) => a.path.compareTo(b.path));
      expect(files, isNotEmpty);
      final growth = <String, int>{};
      for (final file in files) {
        final path = file.path.replaceAll('\\', '/');
        final count = _count(file.readAsStringSync());
        if (count > (_baseline[path] ?? 0)) growth[path] = count;
      }
      expect(
        growth,
        isEmpty,
        reason:
            'Localize new visible literals. Counts: '
            '${jsonEncode(growth)}',
      );
    },
  );
}
