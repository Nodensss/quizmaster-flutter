// Собирает встроенные вопросы (assets/seed/questions.json) из папки с Excel.
//
//   dart run tool/build_seed.dart <папка с Excel> [выходной файл]
//
// Подпапки становятся группами, файлы в них — компетенциями.
// Файлы, лежащие прямо в корне папки, попадают в группу «Общие».
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:quizmaster_flutter/data/backup_format.dart';
import 'package:quizmaster_flutter/data/excel_import.dart';

const _rootGroup = 'Общие';

void main(List<String> args) {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln(
      'Использование: dart run tool/build_seed.dart <папка> [выходной файл]',
    );
    exit(64);
  }
  final root = Directory(args[0]);
  final out = File(args.length > 1 ? args[1] : 'assets/seed/questions.json');
  if (!root.existsSync()) {
    stderr.writeln('Папка не найдена: ${root.path}');
    exit(66);
  }

  final files = root.listSync(recursive: true).whereType<File>().where((f) {
    final name = p.basename(f.path).toLowerCase();
    // ~$file.xlsx — временный файл, который Excel создаёт при открытии.
    return !name.startsWith(r'~$') &&
        (name.endsWith('.xlsx') || name.endsWith('.xls'));
  }).toList()..sort((a, b) => a.path.compareTo(b.path));

  final groups = <String, List<BackupCompetency>>{};
  var total = 0;
  for (final f in files) {
    final parts = p.split(p.relative(f.path, from: root.path));
    final group = parts.length > 1 ? parts.first : _rootGroup;
    final parsed = parseExcelFile(p.basename(f.path), f.readAsBytesSync());
    for (final note in parsed.notes) {
      stderr.writeln('  ! $note');
    }
    if (parsed.questions.isEmpty) continue;
    groups
        .putIfAbsent(group, () => [])
        .add(BackupCompetency(parsed.name, parsed.questions));
    total += parsed.questions.length;
    stdout.writeln('$group / ${parsed.name}: ${parsed.questions.length}');
  }

  if (total == 0) {
    stderr.writeln('Не найдено ни одного вопроса — файл не записан.');
    exit(65);
  }

  final json = encodeBackup([
    for (final e in groups.entries) BackupGroup(e.key, e.value),
  ], seedVersion: DateTime.now().millisecondsSinceEpoch);
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  stdout.writeln(
    '\nГотово: вопросов — $total, групп — ${groups.length} → ${out.path}',
  );
}
