import 'package:sembast/sembast.dart';

import 'backup_format.dart';
import 'db_factory.dart';
import 'excel_import.dart';
import 'models.dart';
import 'text_utils.dart';

class ImportReport {
  int groupsCreated = 0;
  int competenciesCreated = 0;
  int questionsAdded = 0;
  int duplicatesSkipped = 0;
  final List<String> notes = [];
}

/// Всё хранение приложения: группы → компетенции → вопросы,
/// статистика ответов и история попыток.
class QuizRepository {
  QuizRepository(this._db);

  static Future<QuizRepository> open() async =>
      QuizRepository(await openAppDatabase());

  final Database _db;

  static final _groups = intMapStoreFactory.store('groups');
  static final _competencies = intMapStoreFactory.store('competencies');
  static final _questions = intMapStoreFactory.store('questions');
  static final _stats = intMapStoreFactory.store('stats');
  static final _attempts = intMapStoreFactory.store('attempts');
  static final _meta = StoreRef<String, Object?>('meta');

  static const _seedVersionKey = 'seedVersion';

  Future<void> close() => _db.close();

  // --- Группы ---

  Future<List<Group>> groups() async {
    final records = await _groups.find(_db);
    return records.map(_toGroup).toList()
      ..sort((a, b) => compareNames(a.name, b.name));
  }

  Future<int> addGroup(String name) => _groups.add(_db, {'name': name.trim()});

  Future<void> renameGroup(int id, String name) =>
      _groups.record(id).update(_db, {'name': name.trim()});

  Future<void> deleteGroup(int id) => _db.transaction((txn) async {
    final ids = await _competencies.findKeys(
      txn,
      finder: Finder(filter: Filter.equals('group', id)),
    );
    for (final c in ids) {
      await _deleteCompetency(txn, c);
    }
    await _groups.record(id).delete(txn);
  });

  // --- Компетенции ---

  Future<List<Competency>> competencies({int? groupId}) async {
    final records = await _competencies.find(
      _db,
      finder: groupId == null
          ? null
          : Finder(filter: Filter.equals('group', groupId)),
    );
    return records.map(_toCompetency).toList()
      ..sort((a, b) => compareNames(a.name, b.name));
  }

  Future<int> addCompetency(int groupId, String name) =>
      _competencies.add(_db, {'group': groupId, 'name': name.trim()});

  Future<void> renameCompetency(int id, String name) =>
      _competencies.record(id).update(_db, {'name': name.trim()});

  Future<void> deleteCompetency(int id) =>
      _db.transaction((txn) => _deleteCompetency(txn, id));

  Future<void> _deleteCompetency(DatabaseClient client, int id) async {
    final ids = await _questions.findKeys(
      client,
      finder: Finder(filter: Filter.equals('competency', id)),
    );
    await _stats.records(ids).delete(client);
    await _questions.records(ids).delete(client);
    await _competencies.record(id).delete(client);
  }

  // --- Вопросы ---

  /// Количество вопросов в каждой компетенции.
  Future<Map<int, int>> questionCounts() async {
    final out = <int, int>{};
    for (final r in await _questions.find(_db)) {
      final c = r.value['competency'] as int;
      out[c] = (out[c] ?? 0) + 1;
    }
    return out;
  }

  Future<List<Question>> questions(Iterable<int> competencyIds) async {
    final records = await _questions.find(
      _db,
      finder: Finder(
        filter: Filter.inList('competency', competencyIds.toList()),
        sortOrders: [SortOrder(Field.key)],
      ),
    );
    return records.map(_toQuestion).toList();
  }

  Future<int> addQuestion(int competencyId, QuestionDraft q) =>
      _questions.add(_db, _questionValue(competencyId, q));

  Future<void> updateQuestion(int id, int competencyId, QuestionDraft q) =>
      _questions.record(id).put(_db, _questionValue(competencyId, q));

  Future<void> deleteQuestion(int id) => _db.transaction((txn) async {
    await _stats.record(id).delete(txn);
    await _questions.record(id).delete(txn);
  });

  // --- Статистика ответов ---

  Future<void> recordAnswer(int questionId, bool correct) =>
      _db.transaction((txn) async {
        final s = _toStat(await _stats.record(questionId).get(txn));
        await _stats.record(questionId).put(txn, {
          'right': s.right + (correct ? 1 : 0),
          'wrong': s.wrong + (correct ? 0 : 1),
          'last': correct,
        });
      });

  Future<Map<int, QuestionStat>> stats(Iterable<int> questionIds) async {
    final ids = questionIds.toList();
    final values = await _stats.records(ids).get(_db);
    return {
      for (var i = 0; i < ids.length; i++)
        if (values[i] != null) ids[i]: _toStat(values[i]),
    };
  }

  /// Вопросы, на которые в последний раз ответили неправильно.
  Future<List<Question>> mistakes(Iterable<int> competencyIds) async {
    final qs = await questions(competencyIds);
    final st = await stats(qs.map((q) => q.id));
    return qs.where((q) => st[q.id]?.lastCorrect == false).toList();
  }

  /// Количество текущих ошибок в каждой компетенции.
  Future<Map<int, int>> mistakeCounts(Iterable<int> competencyIds) async {
    final out = <int, int>{};
    for (final q in await mistakes(competencyIds)) {
      out[q.competencyId] = (out[q.competencyId] ?? 0) + 1;
    }
    return out;
  }

  // --- История попыток ---

  Future<void> addAttempt({
    required String title,
    required String mode,
    required int total,
    required int score,
  }) => _attempts.add(_db, {
    'time': DateTime.now().millisecondsSinceEpoch,
    'title': title,
    'mode': mode,
    'total': total,
    'score': score,
  });

  Future<List<Attempt>> attempts() async {
    final records = await _attempts.find(
      _db,
      finder: Finder(sortOrders: [SortOrder(Field.key, false)]),
    );
    return [
      for (final r in records)
        Attempt(
          id: r.key,
          time: DateTime.fromMillisecondsSinceEpoch(r.value['time'] as int),
          title: r.value['title'] as String,
          mode: r.value['mode'] as String,
          total: r.value['total'] as int,
          score: r.value['score'] as int,
        ),
    ];
  }

  Future<void> clearAttempts() => _attempts.delete(_db);

  // --- Импорт / экспорт ---

  /// Каждый файл становится компетенцией в группе [groupId].
  /// Уже существующие вопросы (тот же текст и правильный ответ) пропускаются,
  /// поэтому один и тот же файл можно импортировать повторно.
  Future<ImportReport> importExcel(int groupId, List<ParsedFile> files) async {
    final report = ImportReport();
    await _db.transaction((txn) async {
      for (final f in files) {
        report.notes.addAll(f.notes);
        if (f.questions.isEmpty) continue;
        final c = await _ensureCompetency(txn, groupId, f.name, report);
        await _mergeQuestions(txn, c, f.questions, report);
      }
    });
    return report;
  }

  /// Вопросы из всех файлов добавляются в одну компетенцию.
  Future<ImportReport> importIntoCompetency(
    int competencyId,
    List<ParsedFile> files,
  ) async {
    final report = ImportReport();
    await _db.transaction((txn) async {
      for (final f in files) {
        report.notes.addAll(f.notes);
        await _mergeQuestions(txn, competencyId, f.questions, report);
      }
    });
    return report;
  }

  Future<ImportReport> importBackup(List<BackupGroup> groups) async {
    final report = ImportReport();
    await _db.transaction((txn) => _mergeBackup(txn, groups, report));
    return report;
  }

  /// Встроенные вопросы применяются один раз на каждую новую версию файла.
  Future<ImportReport?> applySeed(Map<String, Object?> json) async {
    final version = backupSeedVersion(json);
    final applied = await _meta.record(_seedVersionKey).get(_db) as int? ?? 0;
    if (version <= applied) return null;

    final groups = decodeBackup(json);
    final report = ImportReport();
    await _db.transaction((txn) async {
      await _mergeBackup(txn, groups, report);
      await _meta.record(_seedVersionKey).put(txn, version);
    });
    return report;
  }

  Future<Map<String, Object?>> exportBackup() async {
    final groups = await this.groups();
    final comps = await competencies();
    final qs = await questions(comps.map((c) => c.id));
    return encodeBackup([
      for (final g in groups)
        BackupGroup(g.name, [
          for (final c in comps.where((c) => c.groupId == g.id))
            BackupCompetency(
              c.name,
              qs.where((q) => q.competencyId == c.id).toList(),
            ),
        ]),
    ], seedVersion: DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _mergeBackup(
    DatabaseClient client,
    List<BackupGroup> groups,
    ImportReport report,
  ) async {
    for (final g in groups) {
      final groupId = await _ensureGroup(client, g.name, report);
      for (final c in g.competencies) {
        final compId = await _ensureCompetency(client, groupId, c.name, report);
        await _mergeQuestions(client, compId, c.questions, report);
      }
    }
  }

  Future<int> _ensureGroup(
    DatabaseClient client,
    String name,
    ImportReport report,
  ) async {
    for (final r in await _groups.find(client)) {
      if (normalizeText(r.value['name'] as String) == normalizeText(name)) {
        return r.key;
      }
    }
    report.groupsCreated++;
    return _groups.add(client, {'name': name.trim()});
  }

  Future<int> _ensureCompetency(
    DatabaseClient client,
    int groupId,
    String name,
    ImportReport report,
  ) async {
    final records = await _competencies.find(
      client,
      finder: Finder(filter: Filter.equals('group', groupId)),
    );
    for (final r in records) {
      if (normalizeText(r.value['name'] as String) == normalizeText(name)) {
        return r.key;
      }
    }
    report.competenciesCreated++;
    return _competencies.add(client, {'group': groupId, 'name': name.trim()});
  }

  Future<void> _mergeQuestions(
    DatabaseClient client,
    int competencyId,
    List<QuestionDraft> drafts,
    ImportReport report,
  ) async {
    final existing = await _questions.find(
      client,
      finder: Finder(filter: Filter.equals('competency', competencyId)),
    );
    final keys = {
      for (final r in existing)
        questionKey(r.value['q'] as String, r.value['c'] as String),
    };
    for (final q in drafts) {
      if (!keys.add(questionKey(q.text, q.correct))) {
        report.duplicatesSkipped++;
        continue;
      }
      await _questions.add(client, _questionValue(competencyId, q));
      report.questionsAdded++;
    }
  }

  // --- Преобразование записей ---

  static Map<String, Object?> _questionValue(
    int competencyId,
    QuestionDraft q,
  ) => {
    'competency': competencyId,
    'q': q.text.trim(),
    'c': q.correct.trim(),
    'w': [
      for (final w in q.wrong)
        if (w.trim().isNotEmpty) w.trim(),
    ],
  };

  static Group _toGroup(RecordSnapshot<int, Map<String, Object?>> r) =>
      Group(id: r.key, name: r.value['name'] as String);

  static Competency _toCompetency(
    RecordSnapshot<int, Map<String, Object?>> r,
  ) => Competency(
    id: r.key,
    groupId: r.value['group'] as int,
    name: r.value['name'] as String,
  );

  static Question _toQuestion(RecordSnapshot<int, Map<String, Object?>> r) =>
      Question(
        id: r.key,
        competencyId: r.value['competency'] as int,
        text: r.value['q'] as String,
        correct: r.value['c'] as String,
        wrong: (r.value['w'] as List).cast<String>(),
      );

  static QuestionStat _toStat(Map<String, Object?>? v) => v == null
      ? const QuestionStat()
      : QuestionStat(
          right: v['right'] as int,
          wrong: v['wrong'] as int,
          lastCorrect: v['last'] as bool?,
        );
}
