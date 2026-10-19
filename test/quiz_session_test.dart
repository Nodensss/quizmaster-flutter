import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmaster_flutter/data/models.dart';
import 'package:quizmaster_flutter/quiz/quiz_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Question> _pool(int n) => [
  for (var i = 0; i < n; i++)
    Question(
      id: i + 1,
      competencyId: 7,
      text: 'Q$i',
      correct: 'A$i',
      wrong: ['B$i', 'b$i ', 'C$i'],
    ),
];

int _correctOption(QuizItem it) => it.options.indexWhere((o) => o.correct);

void main() {
  test('builds the requested number of items with deduplicated options', () {
    final s = QuizSession.fromQuestions(
      pool: _pool(10),
      count: 4,
      sources: {7: 'Комп'},
      title: 'T',
      rng: Random(1),
    );
    expect(s.total, 4);
    for (final it in s.items) {
      expect(it.options, hasLength(3), reason: '«B» и «b » — один вариант');
      expect(it.options.where((o) => o.correct), hasLength(1));
      expect(it.source, 'Комп');
    }
  });

  test('scores answers and retries only mistakes', () {
    final s = QuizSession.fromQuestions(
      pool: _pool(3),
      count: 3,
      sources: const {},
      title: 'T',
    );
    s.answers[0] = _correctOption(s.items[0]);
    s.answers[1] = (_correctOption(s.items[1]) + 1) % 3;
    s.answers[2] = _correctOption(s.items[2]);
    s.index = 3;

    expect(s.isFinished, isTrue);
    expect(s.score, 2);
    expect(s.wrongIndexes, [1]);

    final retry = s.retryMistakes(Random(2));
    expect(retry.mode, modeMistakes);
    expect(retry.items.single.text, s.items[1].text);
    expect(retry.answers, [null]);
  });

  test('survives a JSON round trip through SessionStore', () async {
    SharedPreferences.setMockInitialValues({});
    final s = QuizSession.fromQuestions(
      pool: _pool(5),
      count: 5,
      sources: const {},
      title: 'Сохранённый',
    );
    s
      ..answers[0] = 1
      ..index = 1
      ..pending = 2;
    await SessionStore.save(s);

    final restored = (await SessionStore.load())!;
    expect(restored.title, 'Сохранённый');
    expect(restored.index, 1);
    expect(restored.pending, 2);
    expect(restored.answers, s.answers);
    expect(
      restored.items.map((i) => i.questionId),
      s.items.map((i) => i.questionId),
    );
    expect(
      restored.items.first.options.map((o) => (o.text, o.correct)),
      s.items.first.options.map((o) => (o.text, o.correct)),
    );

    await SessionStore.clear();
    expect(await SessionStore.load(), isNull);
  });
}
