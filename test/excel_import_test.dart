import 'package:flutter_test/flutter_test.dart';
import 'package:quizmaster_flutter/data/excel_import.dart';

import 'helpers.dart';

void main() {
  test('reads questions by header names and drops duplicate answers', () {
    final f = parseExcelFile(
      'Охрана труда.xlsx',
      buildXlsx([
        header,
        ['2+2?', 4, 3, 5, 4],
        ['Без ответов', 'Да', null, null, null],
        ['', 'пусто', 'а', 'б', 'в'],
      ]),
    );
    expect(f.name, 'Охрана труда');
    expect(f.notes, isEmpty);
    expect(f.questions, hasLength(1));
    expect(f.questions.single.text, '2+2?');
    expect(f.questions.single.correct, '4');
    expect(f.questions.single.wrong, ['3', '5']);
  });

  test('finds the header below a title row and in any column order', () {
    final f = parseExcelFile(
      'a.xlsx',
      buildXlsx([
        ['Банк вопросов, 2026'],
        [
          'Неверный ответ 1',
          'Текст вопроса',
          'Компетенция',
          'Верный ответ',
          'Неверный ответ 2',
        ],
        ['Нет', 'Столица Франции?', 'География', 'Париж', 'Лион'],
      ]),
    );
    expect(f.notes, isEmpty);
    expect(f.questions.single.text, 'Столица Франции?');
    expect(f.questions.single.correct, 'Париж');
    expect(f.questions.single.wrong, ['Нет', 'Лион']);
  });

  test('falls back to the first five columns when names do not match', () {
    final f = parseExcelFile(
      'b.xlsx',
      buildXlsx([
        ['A', 'B', 'C', 'D', 'E'],
        ['Q', 'C', 'W1', 'W2', 'W3'],
      ]),
    );
    expect(f.notes.single, contains('первые 5 колонок'));
    expect(f.questions.single.wrong, ['W1', 'W2', 'W3']);
  });

  test('reports unreadable and legacy files', () {
    expect(
      parseExcelFile('x.xlsx', [1, 2, 3]).notes.single,
      contains('формат'),
    );
    expect(parseExcelFile('x.xls', [1]).notes.single, contains('.xls'));
  });
}
