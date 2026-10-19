import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../data/text_utils.dart';
import '../quiz/quiz_session.dart';
import 'common.dart';
import 'import_actions.dart';
import 'question_editor.dart';
import 'quiz_launcher.dart';

class CompetencyScreen extends StatefulWidget {
  const CompetencyScreen({
    super.key,
    required this.repo,
    required this.competency,
  });

  final QuizRepository repo;
  final Competency competency;

  @override
  State<CompetencyScreen> createState() => _CompetencyScreenState();
}

class _CompetencyScreenState extends State<CompetencyScreen> {
  QuizRepository get _repo => widget.repo;
  int get _id => widget.competency.id;

  late String _name = widget.competency.name;
  var _loading = true;
  List<Question> _questions = [];
  Map<int, QuestionStat> _stats = {};
  var _query = '';

  List<Question> get _mistakes =>
      _questions.where((q) => _stats[q.id]?.lastCorrect == false).toList();

  List<Question> get _visible {
    final q = normalizeText(_query);
    if (q.isEmpty) return _questions;
    return _questions
        .where(
          (x) =>
              normalizeText(x.text).contains(q) ||
              normalizeText(x.correct).contains(q),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final qs = await _repo.questions([_id]);
    final stats = await _repo.stats(qs.map((q) => q.id));
    if (!mounted) return;
    setState(() {
      _questions = qs;
      _stats = stats;
      _loading = false;
    });
  }

  Future<void> _edit([Question? q]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            QuestionEditor(repo: _repo, competencyId: _id, question: q),
      ),
    );
    if (changed == true) await _reload();
  }

  Future<void> _quiz({required bool mistakes}) async {
    await startQuiz(
      context,
      _repo,
      title: _name,
      pool: mistakes ? _mistakes : _questions,
      sources: {_id: _name},
      mode: mistakes ? modeMistakes : modeMain,
    );
    await _reload();
  }

  Future<void> _menu(String action) async {
    switch (action) {
      case 'import':
        if (await importExcelToCompetency(context, _repo, _id)) {
          await _reload();
        }
      case 'rename':
        final name = await askName(
          context,
          title: 'Переименовать компетенцию',
          initial: _name,
        );
        if (name == null) return;
        await _repo.renameCompetency(_id, name);
        setState(() => _name = name);
      case 'delete':
        final ok = await confirm(
          context,
          title: 'Удалить компетенцию?',
          message:
              '«$_name» будет удалена вместе с ${questionsLabel(_questions.length)}.',
        );
        if (!ok) return;
        await _repo.deleteCompetency(_id);
        if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        title: Text(_name),
        actions: [
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: Text('Добавить из Excel')),
              PopupMenuItem(value: 'rename', child: Text('Переименовать')),
              PopupMenuItem(
                value: 'delete',
                child: Text('Удалить компетенцию'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: const Text('Вопрос'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: visible.length + 2,
              itemBuilder: (context, i) {
                if (i == 0) return _summary();
                if (i == 1) return _search();
                return _tile(visible[i - 2]);
              },
            ),
    );
  }

  Widget _summary() {
    final mistakes = _mistakes.length;
    final answered = _questions.where((q) => _stats[q.id] != null).length;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(questionsLabel(_questions.length)),
            if (answered > 0)
              Text(
                'Отвечено: $answered · сейчас с ошибкой: $mistakes',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _questions.isEmpty
                      ? null
                      : () => _quiz(mistakes: false),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Начать тест'),
                ),
                if (mistakes > 0)
                  OutlinedButton(
                    onPressed: () => _quiz(mistakes: true),
                    child: Text('Работа над ошибками ($mistakes)'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _search() {
    if (_questions.isEmpty) {
      return const EmptyState(
        icon: Icons.help_outline,
        text:
            'Вопросов пока нет.\nДобавьте вопрос кнопкой «Вопрос» '
            'или загрузите Excel через меню.',
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Поиск по вопросам',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (v) => setState(() => _query = v),
      ),
    );
  }

  Widget _tile(Question q) {
    final last = _stats[q.id]?.lastCorrect;
    return ListTile(
      title: Text(q.text, maxLines: 3, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '✓ ${q.correct}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: last == null
          ? null
          : Icon(
              last ? Icons.check_circle_outline : Icons.error_outline,
              color: last
                  ? Colors.green.shade600
                  : Theme.of(context).colorScheme.error,
            ),
      onTap: () => _edit(q),
    );
  }
}
