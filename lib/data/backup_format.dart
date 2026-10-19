import 'models.dart';

/// JSON-формат базы вопросов. Он же используется для экспорта/импорта
/// и для встроенных вопросов (assets/seed/questions.json).
///
/// ```json
/// {"format": "quizmaster", "version": 1, "seedVersion": 1700000000000,
///  "groups": [{"name": "...", "competencies": [{"name": "...",
///    "questions": [{"q": "...", "c": "...", "w": ["...", "..."]}]}]}]}
/// ```
const backupFormat = 'quizmaster';
const backupFormatVersion = 1;

class BackupCompetency {
  const BackupCompetency(this.name, this.questions);

  final String name;
  final List<QuestionDraft> questions;
}

class BackupGroup {
  const BackupGroup(this.name, this.competencies);

  final String name;
  final List<BackupCompetency> competencies;
}

Map<String, Object?> encodeBackup(
  List<BackupGroup> groups, {
  required int seedVersion,
}) => {
  'format': backupFormat,
  'version': backupFormatVersion,
  'seedVersion': seedVersion,
  'groups': [
    for (final g in groups)
      {
        'name': g.name,
        'competencies': [
          for (final c in g.competencies)
            {
              'name': c.name,
              'questions': [
                for (final q in c.questions)
                  {'q': q.text, 'c': q.correct, 'w': q.wrong},
              ],
            },
        ],
      },
  ],
};

int backupSeedVersion(Map<String, Object?> json) {
  final v = json['seedVersion'];
  return v is num ? v.toInt() : 0;
}

/// Бросает [FormatException], если это не файл базы вопросов.
List<BackupGroup> decodeBackup(Object? json) {
  if (json is! Map || json['format'] != backupFormat) {
    throw const FormatException('Это не файл базы вопросов.');
  }
  final version = json['version'];
  if (version is! num || version > backupFormatVersion) {
    throw const FormatException('Файл создан более новой версией приложения.');
  }

  String str(Object? v) => v is String ? v.trim() : '';
  List<Map> list(Object? v) => v is List ? v.whereType<Map>().toList() : [];

  return [
    for (final g in list(json['groups']))
      if (str(g['name']).isNotEmpty)
        BackupGroup(str(g['name']), [
          for (final c in list(g['competencies']))
            if (str(c['name']).isNotEmpty)
              BackupCompetency(str(c['name']), [
                for (final q in list(c['questions']))
                  if (str(q['q']).isNotEmpty && str(q['c']).isNotEmpty)
                    QuestionDraft(
                      text: str(q['q']),
                      correct: str(q['c']),
                      wrong: [
                        if (q['w'] is List)
                          for (final w in q['w'] as List)
                            if (str(w).isNotEmpty) str(w),
                      ],
                    ),
              ]),
        ]),
  ];
}
