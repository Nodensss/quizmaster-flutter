import 'package:flutter_test/flutter_test.dart';
import 'package:quizmaster_flutter/data/backup_format.dart';
import 'package:quizmaster_flutter/data/excel_import.dart';
import 'package:quizmaster_flutter/data/models.dart';
import 'package:quizmaster_flutter/data/repository.dart';

import 'helpers.dart';

const _q1 = QuestionDraft(text: 'Q1', correct: 'A', wrong: ['B', 'C']);
const _q2 = QuestionDraft(text: 'Q2', correct: 'A', wrong: ['B']);

ParsedFile _file(String name, List<QuestionDraft> qs) =>
    ParsedFile(name: name, questions: qs, notes: const []);

Future<QuizRepository> _repo() => memoryRepository();

void main() {
  test('excel import creates competencies and skips duplicates', () async {
    final repo = await _repo();
    final g = await repo.addGroup('Электрики');

    var r = await repo.importExcel(g, [
      _file('ТБ', [_q1, _q2]),
      _file('ПТЭ', [_q1]),
    ]);
    expect(r.competenciesCreated, 2);
    expect(r.questionsAdded, 3);

    r = await repo.importExcel(g, [
      _file('тб', [
        _q1,
        const QuestionDraft(text: 'Q3', correct: 'X', wrong: ['Y']),
      ]),
    ]);
    expect(r.competenciesCreated, 0, reason: 'имя сравнивается без регистра');
    expect(r.questionsAdded, 1);
    expect(r.duplicatesSkipped, 1);

    final comps = await repo.competencies(groupId: g);
    expect(comps.map((c) => c.name), ['ПТЭ', 'ТБ']);
    expect(await repo.questionCounts(), {comps[0].id: 1, comps[1].id: 3});
  });

  test('editing, mistakes and cascade delete', () async {
    final repo = await _repo();
    final g = await repo.addGroup('G');
    final c = await repo.addCompetency(g, 'C');
    final id = await repo.addQuestion(c, _q1);

    await repo.updateQuestion(
      id,
      c,
      const QuestionDraft(text: 'Q1 правка', correct: 'A', wrong: ['B', ' ']),
    );
    final q = (await repo.questions([c])).single;
    expect(q.text, 'Q1 правка');
    expect(q.wrong, ['B']);

    await repo.recordAnswer(id, false);
    expect((await repo.mistakes([c])).single.id, id);
    expect(await repo.mistakeCounts([c]), {c: 1});
    await repo.recordAnswer(id, true);
    expect(await repo.mistakes([c]), isEmpty);
    final st = (await repo.stats([id]))[id]!;
    expect((st.right, st.wrong, st.lastCorrect), (1, 1, true));

    await repo.deleteGroup(g);
    expect(await repo.groups(), isEmpty);
    expect(await repo.competencies(), isEmpty);
    expect(await repo.questions([c]), isEmpty);
    expect(await repo.stats([id]), isEmpty);
  });

  test('backup round trip merges into another database', () async {
    final a = await _repo();
    final g = await a.addGroup('Группа');
    await a.importExcel(g, [
      _file('Комп', [_q1, _q2]),
    ]);
    final json = await a.exportBackup();

    final b = await _repo();
    final groups = decodeBackup(json);
    var r = await b.importBackup(groups);
    expect(
      (r.groupsCreated, r.competenciesCreated, r.questionsAdded),
      (1, 1, 2),
    );
    r = await b.importBackup(groups);
    expect((r.groupsCreated, r.questionsAdded, r.duplicatesSkipped), (0, 0, 2));

    final qs = await b.questions((await b.competencies()).map((c) => c.id));
    expect(qs.map((q) => q.text), ['Q1', 'Q2']);
    expect(qs.first.wrong, ['B', 'C']);
  });

  test('seed is applied once per version', () async {
    final repo = await _repo();
    Map<String, Object?> seed(int version) => encodeBackup([
      BackupGroup('Встроенные', [
        BackupCompetency('К', [_q1]),
      ]),
    ], seedVersion: version);

    expect(await repo.applySeed(seed(0)), isNull);
    expect((await repo.applySeed(seed(5)))!.questionsAdded, 1);
    expect(await repo.applySeed(seed(5)), isNull);
    expect((await repo.applySeed(seed(6)))!.duplicatesSkipped, 1);
    expect(await repo.groups(), hasLength(1));
  });

  test('decodeBackup rejects foreign files', () {
    expect(() => decodeBackup({'a': 1}), throwsFormatException);
    expect(
      () => decodeBackup({'format': backupFormat, 'version': 99}),
      throwsFormatException,
    );
  });

  test('attempts are listed newest first and can be cleared', () async {
    final repo = await _repo();
    await repo.addAttempt(title: 'A', mode: 'Тест', total: 10, score: 7);
    await repo.addAttempt(title: 'B', mode: 'Тест', total: 4, score: 4);
    final list = await repo.attempts();
    expect(list.map((a) => a.title), ['B', 'A']);
    expect(list.last.percent, 70);
    await repo.clearAttempts();
    expect(await repo.attempts(), isEmpty);
  });
}
