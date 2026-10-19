import 'package:excel/excel.dart';
import 'package:quizmaster_flutter/data/repository.dart';
import 'package:sembast/sembast_memory.dart';

List<int> buildXlsx(List<List<Object?>> rows) {
  final excel = Excel.createExcel();
  final sheet = excel[excel.getDefaultSheet()!];
  for (final r in rows) {
    sheet.appendRow([
      for (final v in r)
        switch (v) {
          null => null,
          int n => IntCellValue(n),
          _ => TextCellValue('$v'),
        },
    ]);
  }
  return excel.encode()!;
}

const header = [
  'Вопрос',
  'Правильный ответ',
  'Неправильный ответ 1',
  'Неправильный ответ 2',
  'Неправильный ответ 3',
];

var _dbCounter = 0;

Future<QuizRepository> memoryRepository() async => QuizRepository(
  await newDatabaseFactoryMemory().openDatabase('test_${_dbCounter++}.db'),
);
