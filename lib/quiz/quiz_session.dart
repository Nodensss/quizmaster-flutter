import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/text_utils.dart';

const modeMain = 'Тест';
const modeMistakes = 'Работа над ошибками';

class QuizOption {
  const QuizOption(this.text, this.correct);

  final String text;
  final bool correct;
}

class QuizItem {
  const QuizItem({
    required this.questionId,
    required this.text,
    required this.correct,
    required this.source,
    required this.options,
  });

  final int? questionId;
  final String text;
  final String correct;

  /// Название компетенции, из которой взят вопрос.
  final String source;
  final List<QuizOption> options;

  QuizItem reshuffled(Random rng) => QuizItem(
    questionId: questionId,
    text: text,
    correct: correct,
    source: source,
    options: [...options]..shuffle(rng),
  );
}

class QuizSession {
  QuizSession({
    required this.title,
    required this.mode,
    required this.items,
    this.index = 0,
    List<int?>? answers,
    this.pending,
    this.saved = false,
  }) : answers = answers ?? List<int?>.filled(items.length, null);

  /// Собирает тест из [count] случайных вопросов пула.
  /// [sources] — названия компетенций по их id.
  factory QuizSession.fromQuestions({
    required List<Question> pool,
    required int count,
    required Map<int, String> sources,
    required String title,
    String mode = modeMain,
    Random? rng,
  }) {
    final random = rng ?? Random();
    final items = <QuizItem>[];
    for (final q in [...pool]..shuffle(random)) {
      if (items.length >= count) break;
      final seen = <String>{};
      final options = [
        for (final (text, ok) in [
          (q.correct, true),
          for (final w in q.wrong) (w, false),
        ])
          if (text.trim().isNotEmpty && seen.add(normalizeText(text)))
            QuizOption(text.trim(), ok),
      ];
      if (options.length < 2) continue;
      items.add(
        QuizItem(
          questionId: q.id,
          text: q.text,
          correct: q.correct,
          source: sources[q.competencyId] ?? '',
          options: options..shuffle(random),
        ),
      );
    }
    return QuizSession(title: title, mode: mode, items: items);
  }

  final String title;
  final String mode;
  final List<QuizItem> items;

  /// Текущий вопрос; `index == total` — тест завершён.
  int index;

  /// Выбранный вариант для каждого проверенного вопроса.
  final List<int?> answers;

  /// Выбранный, но ещё не проверенный вариант текущего вопроса.
  int? pending;

  /// Попытка уже записана в историю.
  bool saved;

  int get total => items.length;
  bool get isFinished => index >= total;
  QuizItem get current => items[index];
  int? get currentAnswer => answers[index];
  bool get isChecked => !isFinished && answers[index] != null;

  bool isCorrect(int i) =>
      answers[i] != null && items[i].options[answers[i]!].correct;

  int get score => [for (var i = 0; i < total; i++) i].where(isCorrect).length;

  List<int> get wrongIndexes => [
    for (var i = 0; i < total; i++)
      if (answers[i] != null && !isCorrect(i)) i,
  ];

  /// Новая сессия только из ошибок, с перемешанными вариантами.
  QuizSession retryMistakes([Random? rng]) {
    final random = rng ?? Random();
    return QuizSession(
      title: title,
      mode: modeMistakes,
      items: [for (final i in wrongIndexes) items[i].reshuffled(random)]
        ..shuffle(random),
    );
  }

  Map<String, Object?> toJson() => {
    'title': title,
    'mode': mode,
    'index': index,
    'answers': answers,
    'pending': pending,
    'saved': saved,
    'items': [
      for (final it in items)
        {
          'id': it.questionId,
          'q': it.text,
          'c': it.correct,
          's': it.source,
          'o': [
            for (final o in it.options) {'t': o.text, 'ok': o.correct},
          ],
        },
    ],
  };

  static QuizSession fromJson(Map<String, Object?> m) {
    final items = [
      for (final it in (m['items'] as List).cast<Map>())
        QuizItem(
          questionId: it['id'] as int?,
          text: it['q'] as String,
          correct: it['c'] as String,
          source: it['s'] as String? ?? '',
          options: [
            for (final o in (it['o'] as List).cast<Map>())
              QuizOption(o['t'] as String, o['ok'] as bool),
          ],
        ),
    ];
    final answers = (m['answers'] as List).cast<int?>().toList();
    if (answers.length != items.length) {
      throw const FormatException('Повреждённая сессия');
    }
    return QuizSession(
      title: m['title'] as String,
      mode: m['mode'] as String,
      items: items,
      index: (m['index'] as int).clamp(0, items.length),
      answers: answers,
      pending: m['pending'] as int?,
      saved: m['saved'] as bool? ?? false,
    );
  }
}

/// Незавершённый тест хранится между запусками приложения.
class SessionStore {
  static const _key = 'quizmaster_active_session_v2';

  static Future<QuizSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final s = QuizSession.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
      return s.isFinished && s.saved ? null : s;
    } catch (_) {
      await prefs.remove(_key);
      return null;
    }
  }

  static Future<void> save(QuizSession s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(s.toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
