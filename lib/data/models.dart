class Group {
  const Group({required this.id, required this.name});

  final int id;
  final String name;
}

class Competency {
  const Competency({
    required this.id,
    required this.groupId,
    required this.name,
  });

  final int id;
  final int groupId;
  final String name;
}

/// Вопрос без привязки к базе: результат разбора Excel/JSON или данные формы.
class QuestionDraft {
  const QuestionDraft({
    required this.text,
    required this.correct,
    required this.wrong,
  });

  final String text;
  final String correct;
  final List<String> wrong;
}

class Question extends QuestionDraft {
  const Question({
    required this.id,
    required this.competencyId,
    required super.text,
    required super.correct,
    required super.wrong,
  });

  final int id;
  final int competencyId;
}

class QuestionStat {
  const QuestionStat({this.right = 0, this.wrong = 0, this.lastCorrect});

  final int right;
  final int wrong;
  final bool? lastCorrect;
}

class Attempt {
  const Attempt({
    required this.id,
    required this.time,
    required this.title,
    required this.mode,
    required this.total,
    required this.score,
  });

  final int id;
  final DateTime time;
  final String title;
  final String mode;
  final int total;
  final int score;

  double get percent => total == 0 ? 0 : score / total * 100;
}
