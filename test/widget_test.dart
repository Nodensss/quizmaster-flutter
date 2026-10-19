import 'package:flutter_test/flutter_test.dart';
import 'package:quizmaster_flutter/data/excel_import.dart';
import 'package:quizmaster_flutter/data/models.dart';
import 'package:quizmaster_flutter/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

Future<void> _settle(WidgetTester tester) async {
  // База работает на настоящих Future, поэтому даём им выполниться.
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('empty database shows import hint', (tester) async {
    final repo = (await tester.runAsync(memoryRepository))!;
    await tester.pumpWidget(QuizApp(openRepository: () async => repo));
    await _settle(tester);

    expect(find.text('Тренажёр викторин'), findsOneWidget);
    expect(find.text('Импорт Excel'), findsOneWidget);
  });

  testWidgets('group → competency → quiz → result', (tester) async {
    final repo = (await tester.runAsync(() async {
      final r = await memoryRepository();
      final g = await r.addGroup('Электрики');
      await r.importExcel(g, [
        const ParsedFile(
          name: 'Охрана труда',
          questions: [
            QuestionDraft(
              text: 'Сколько будет 2+2?',
              correct: '4',
              wrong: ['5'],
            ),
          ],
          notes: [],
        ),
      ]);
      return r;
    }))!;

    await tester.pumpWidget(QuizApp(openRepository: () async => repo));
    await _settle(tester);
    expect(find.text('1 компетенция · 1 вопрос'), findsOneWidget);

    await tester.tap(find.text('Электрики'));
    await _settle(tester);
    await tester.tap(find.text('Охрана труда'));
    await _settle(tester);
    expect(find.text('Сколько будет 2+2?'), findsOneWidget);

    await tester.tap(find.text('Начать тест'));
    await _settle(tester);
    await tester.tap(find.text('5'));
    await tester.pump();
    await tester.tap(find.text('Проверить'));
    await _settle(tester);
    expect(find.text('Неверно. Правильный ответ: 4'), findsOneWidget);

    await tester.tap(find.text('Завершить'));
    await _settle(tester);
    expect(find.text('0 из 1 (0.0%)'), findsOneWidget);

    await tester.tap(find.text('Готово'));
    await _settle(tester);
    expect(find.text('Работа над ошибками (1)'), findsOneWidget);

    final history = (await tester.runAsync(repo.attempts))!;
    expect(history.single.title, 'Охрана труда');
  });
}
