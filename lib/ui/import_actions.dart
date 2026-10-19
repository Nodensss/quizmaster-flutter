import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/backup_format.dart';
import '../data/excel_import.dart';
import '../data/repository.dart';
import 'common.dart';

/// Выбор и разбор Excel-файлов. `null` — пользователь отменил выбор.
Future<List<ParsedFile>?> pickExcelFiles(BuildContext context) async {
  final FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls'],
      withData: true,
    );
  } catch (_) {
    if (context.mounted) toast(context, 'Не удалось открыть выбор файлов.');
    return null;
  }
  if (picked == null || picked.files.isEmpty || !context.mounted) return null;

  final sources = [
    for (final f in picked.files) ExcelSource(f.name, f.bytes ?? const []),
  ];
  return withProgress(
    context,
    'Читаю файлы…',
    compute(parseExcelFiles, sources),
  );
}

/// Каждый файл — компетенция внутри группы [groupId].
Future<bool> importExcelToGroup(
  BuildContext context,
  QuizRepository repo,
  int groupId,
) async {
  final files = await pickExcelFiles(context);
  if (files == null || !context.mounted) return false;
  final report = await withProgress(
    context,
    'Сохраняю вопросы…',
    repo.importExcel(groupId, files),
  );
  if (context.mounted) await showImportReport(context, report);
  return true;
}

/// Все вопросы из выбранных файлов — в одну компетенцию.
Future<bool> importExcelToCompetency(
  BuildContext context,
  QuizRepository repo,
  int competencyId,
) async {
  final files = await pickExcelFiles(context);
  if (files == null || !context.mounted) return false;
  final report = await withProgress(
    context,
    'Сохраняю вопросы…',
    repo.importIntoCompetency(competencyId, files),
  );
  if (context.mounted) await showImportReport(context, report);
  return true;
}

Future<void> exportBackupFile(BuildContext context, QuizRepository repo) async {
  final data = await repo.exportBackup();
  final bytes = Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
  );
  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить базу вопросов',
      fileName: 'questions.json',
      bytes: bytes,
    );
    if (context.mounted && (path != null || kIsWeb)) {
      toast(context, 'База сохранена в questions.json');
    }
  } catch (_) {
    if (context.mounted) toast(context, 'Не удалось сохранить файл.');
  }
}

Future<bool> importBackupFile(BuildContext context, QuizRepository repo) async {
  final FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
  } catch (_) {
    if (context.mounted) toast(context, 'Не удалось открыть выбор файлов.');
    return false;
  }
  final bytes = picked?.files.single.bytes;
  if (bytes == null || !context.mounted) return false;

  final List<BackupGroup> groups;
  try {
    groups = decodeBackup(jsonDecode(utf8.decode(bytes)));
  } on FormatException catch (e) {
    toast(context, 'Не удалось прочитать файл: ${e.message}');
    return false;
  }
  final report = await withProgress(
    context,
    'Загружаю базу…',
    repo.importBackup(groups),
  );
  if (context.mounted) await showImportReport(context, report);
  return true;
}
