import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../quiz/quiz_session.dart';
import 'common.dart';
import 'competency_screen.dart';
import 'import_actions.dart';
import 'quiz_launcher.dart';

class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.repo, required this.group});

  final QuizRepository repo;
  final Group group;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  QuizRepository get _repo => widget.repo;

  late String _name = widget.group.name;
  var _loading = true;
  List<Competency> _competencies = [];
  Map<int, int> _counts = {};
  Map<int, int> _mistakes = {};

  int get _total => _competencies.fold(0, (s, c) => s + (_counts[c.id] ?? 0));
  int get _totalMistakes => _mistakes.values.fold(0, (s, n) => s + n);
  Map<int, String> get _sources => {
    for (final c in _competencies) c.id: c.name,
  };

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final comps = await _repo.competencies(groupId: widget.group.id);
    final counts = await _repo.questionCounts();
    final mistakes = await _repo.mistakeCounts(comps.map((c) => c.id));
    if (!mounted) return;
    setState(() {
      _competencies = comps;
      _counts = counts;
      _mistakes = mistakes;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final name = await askName(
      context,
      title: 'Новая компетенция',
      action: 'Создать',
    );
    if (name == null) return;
    await _repo.addCompetency(widget.group.id, name);
    await _reload();
  }

  Future<void> _renameCompetency(Competency c) async {
    final name = await askName(
      context,
      title: 'Переименовать компетенцию',
      initial: c.name,
    );
    if (name == null) return;
    await _repo.renameCompetency(c.id, name);
    await _reload();
  }

  Future<void> _deleteCompetency(Competency c) async {
    final ok = await confirm(
      context,
      title: 'Удалить компетенцию?',
      message:
          '«${c.name}» будет удалена вместе с ${questionsLabel(_counts[c.id] ?? 0)}.',
    );
    if (!ok) return;
    await _repo.deleteCompetency(c.id);
    await _reload();
  }

  Future<void> _menu(String action) async {
    switch (action) {
      case 'rename':
        final name = await askName(
          context,
          title: 'Переименовать группу',
          initial: _name,
        );
        if (name == null) return;
        await _repo.renameGroup(widget.group.id, name);
        setState(() => _name = name);
      case 'delete':
        final ok = await confirm(
          context,
          title: 'Удалить группу?',
          message:
              '«$_name» будет удалена вместе со всеми компетенциями и вопросами.',
        );
        if (!ok) return;
        await _repo.deleteGroup(widget.group.id);
        if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _quiz({required bool mistakes}) async {
    final ids = _competencies.map((c) => c.id);
    final pool = mistakes
        ? await _repo.mistakes(ids)
        : await _repo.questions(ids);
    if (!mounted) return;
    await startQuiz(
      context,
      _repo,
      title: _name,
      pool: pool,
      sources: _sources,
      mode: mistakes ? modeMistakes : modeMain,
    );
    await _reload();
  }

  Future<void> _import() async {
    if (await importExcelToGroup(context, _repo, widget.group.id)) {
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_name),
        actions: [
          IconButton(
            tooltip: 'Импорт Excel в эту группу',
            icon: const Icon(Icons.upload_file),
            onPressed: _import,
          ),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'rename',
                child: Text('Переименовать группу'),
              ),
              PopupMenuItem(value: 'delete', child: Text('Удалить группу')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Компетенция'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                if (_competencies.isEmpty)
                  EmptyState(
                    icon: Icons.topic_outlined,
                    text:
                        'В группе пока нет компетенций.\nИмпортируйте Excel-файлы '
                        'или создайте компетенцию вручную.',
                    actions: [
                      FilledButton.icon(
                        onPressed: _import,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Импорт Excel'),
                      ),
                    ],
                  )
                else
                  _summary(),
                for (final c in _competencies) _tile(c),
              ],
            ),
    );
  }

  Widget _summary() {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${plural(_competencies.length, 'компетенция', 'компетенции', 'компетенций')}'
              ' · ${questionsLabel(_total)}',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _total == 0 ? null : () => _quiz(mistakes: false),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Тест по всей группе'),
                ),
                if (_totalMistakes > 0)
                  OutlinedButton(
                    onPressed: () => _quiz(mistakes: true),
                    child: Text('Ошибки ($_totalMistakes)'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Competency c) {
    final mistakes = _mistakes[c.id] ?? 0;
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.topic_outlined)),
      title: Text(c.name),
      subtitle: Text(
        '${questionsLabel(_counts[c.id] ?? 0)}'
        '${mistakes > 0 ? ' · ошибок: $mistakes' : ''}',
      ),
      trailing: ItemMenu(
        onRename: () => _renameCompetency(c),
        onDelete: () => _deleteCompetency(c),
      ),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CompetencyScreen(repo: _repo, competency: c),
          ),
        );
        await _reload();
      },
    );
  }
}
