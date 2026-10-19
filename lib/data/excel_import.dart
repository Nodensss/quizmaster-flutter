import 'dart:math';

import 'package:excel/excel.dart';

import 'models.dart';
import 'text_utils.dart';

const _wrongFields = ['wrong1', 'wrong2', 'wrong3'];
const _required = ['question', 'correct', ..._wrongFields];
const _aliases = {
  'question': ['Вопрос', 'Question', 'Текст вопроса'],
  'correct': ['Правильный ответ', 'Верный ответ', 'Correct answer'],
  'wrong1': ['Неправильный ответ 1', 'Неверный ответ 1', 'Wrong answer 1'],
  'wrong2': ['Неправильный ответ 2', 'Неверный ответ 2', 'Wrong answer 2'],
  'wrong3': ['Неправильный ответ 3', 'Неверный ответ 3', 'Wrong answer 3'],
};

/// Сколько первых строк просматривать в поисках заголовка
/// (над таблицей бывает название документа).
const _headerScanRows = 10;

class ExcelSource {
  const ExcelSource(this.fileName, this.bytes);

  final String fileName;
  final List<int> bytes;
}

class ParsedFile {
  const ParsedFile({
    required this.name,
    required this.questions,
    required this.notes,
  });

  /// Имя файла без расширения — так называется компетенция.
  final String name;
  final List<QuestionDraft> questions;
  final List<String> notes;
}

/// Верхнеуровневая функция, чтобы её можно было передать в `compute`.
List<ParsedFile> parseExcelFiles(List<ExcelSource> sources) =>
    sources.map((s) => parseExcelFile(s.fileName, s.bytes)).toList();

ParsedFile parseExcelFile(String fileName, List<int> bytes) {
  final name = fileLabel(fileName);
  final notes = <String>[];
  ParsedFile result(List<QuestionDraft> qs) =>
      ParsedFile(name: name, questions: qs, notes: notes);

  if (fileName.toLowerCase().endsWith('.xls')) {
    notes.add(
      '$fileName: формат .xls не поддерживается, сохраните файл как .xlsx.',
    );
    return result(const []);
  }
  if (bytes.isEmpty) {
    notes.add('$fileName: не удалось прочитать файл.');
    return result(const []);
  }

  final Excel wb;
  try {
    wb = Excel.decodeBytes(bytes);
  } catch (_) {
    notes.add('$fileName: неверный формат или повреждённый файл.');
    return result(const []);
  }

  final sheet = wb.tables.values
      .where((t) => t.rows.isNotEmpty)
      .cast<Sheet?>()
      .firstWhere((_) => true, orElse: () => null);
  if (sheet == null) {
    notes.add('$fileName: нет листов с данными.');
    return result(const []);
  }

  final rows = sheet.rows
      .map((r) => r.map(_cell).toList())
      .toList(growable: false);

  var headerRow = -1;
  Map<String, int> columns = const {};
  for (var i = 0; i < rows.length && i < _headerScanRows; i++) {
    final found = _matchHeader(rows[i]);
    if (found.containsKey('question') && found.containsKey('correct')) {
      headerRow = i;
      columns = found;
      break;
    }
  }

  final hasWrong = _wrongFields.any(columns.containsKey);
  if (headerRow < 0 || !hasWrong) {
    final width = rows[max(headerRow, 0)].length;
    if (width < _required.length) {
      notes.add(
        '$fileName: не найдены колонки «Вопрос», «Правильный ответ», '
        '«Неправильный ответ 1–3».',
      );
      return result(const []);
    }
    if (headerRow < 0) headerRow = 0;
    columns = {for (var i = 0; i < _required.length; i++) _required[i]: i};
    notes.add(
      '$fileName: имена колонок не совпали, использованы первые 5 колонок.',
    );
  }

  String read(List<String> row, String key) {
    final i = columns[key];
    return i != null && i < row.length ? row[i] : '';
  }

  final out = <QuestionDraft>[];
  for (final row in rows.skip(headerRow + 1)) {
    final q = read(row, 'question');
    final c = read(row, 'correct');
    if (q.isEmpty || c.isEmpty) continue;

    final wrong = <String>[];
    final seen = {normalizeText(c)};
    for (final k in _wrongFields) {
      final v = read(row, k);
      if (v.isNotEmpty && seen.add(normalizeText(v))) wrong.add(v);
    }
    if (wrong.isEmpty) continue;

    out.add(QuestionDraft(text: q, correct: c, wrong: wrong));
  }

  if (out.isEmpty) {
    notes.add('$fileName: после очистки не осталось валидных строк.');
  }
  return result(out);
}

Map<String, int> _matchHeader(List<String> row) {
  final index = <String, int>{};
  for (var i = 0; i < row.length; i++) {
    index.putIfAbsent(normalizeHeader(row[i]), () => i);
  }
  final out = <String, int>{};
  for (final field in _required) {
    for (final alias in _aliases[field]!) {
      final i = index[normalizeHeader(alias)];
      if (i != null) {
        out[field] = i;
        break;
      }
    }
  }
  return out;
}

String _cell(Data? x) {
  final v = x?.value;
  return v == null ? '' : '$v'.trim();
}
