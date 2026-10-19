import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../quiz/quiz_session.dart';
import 'common.dart';
import 'group_screen.dart';
import 'history_screen.dart';
import 'import_actions.dart';
import 'quiz_launcher.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repo});

  final QuizRepository repo;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  QuizRepository get _repo => widget.repo;

  var _loading = true;
  List<Group> _groups = [];
  List<Competency> _competencies = [];
  Map<int, int> _counts = {};
  QuizSession? _active;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final groups = await _repo.groups();
    final competencies = await _repo.competencies();
    final counts = await _repo.questionCounts();
    final active = await SessionStore.load();
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _competencies = competencies;
      _counts = counts;
      _active = active;
      _loading = false;
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    await _reload();
  }

  Future<void> _addGroup() async {
    final name = await askName(
      context,
      title: 'Новая группа',
      action: 'Создать',
    );
    if (name == null) return;
    await _repo.addGroup(name);
    await _reload();
  }

  Future<void> _rename(Group g) async {
    final name = await askName(
      context,
      title: 'Переименовать группу',
      initial: g.name,
    );
    if (name == null) return;
    await _repo.renameGroup(g.id, name);
    await _reload();
  }

  Future<void> _delete(Group g) async {
    final ok = await confirm(
      context,
      title: 'Удалить группу?',
      message:
          '«${g.name}» будет удалена вместе со всеми компетенциями и вопросами.',
    );
    if (!ok) return;
    await _repo.deleteGroup(g.id);
    await _reload();
  }

  /// Импорт с главного экрана: сначала файлы, потом группа для них.
  Future<void> _importExcel() async {
    final files = await pickExcelFiles(context);
    if (files == null || !mounted) return;
    final groupId = await _chooseGroup();
    if (groupId == null || !mounted) return;
    final report = await withProgress(
      context,
      'Сохраняю вопросы…',
      _repo.importExcel(groupId, files),
    );
    await _reload();
    if (mounted) await showImportReport(context, report);
  }

  Future<int?> _chooseGroup() async {
    const newGroup = -1;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('В какую группу добавить?'),
        children: [
          for (final g in _groups)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, g.id),
              child: Text(g.name),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, newGroup),
            child: const Row(
              children: [
                Icon(Icons.add),
                SizedBox(width: 8),
                Text('Новая группа…'),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != newGroup || !mounted) return picked;
    final name = await askName(
      context,
      title: 'Новая группа',
      action: 'Создать',
    );
    return name == null ? null : _repo.addGroup(name);
  }

  Future<void> _menu(String action) async {
    switch (action) {
      case 'import':
        await _importExcel();
      case 'export':
        await exportBackupFile(context, _repo);
      case 'restore':
        if (await importBackupFile(context, _repo)) await _reload();
    }
  }

  Future<void> _continueQuiz(QuizSession s) async {
    await openQuiz(context, _repo, s);
    await _reload();
  }

  Future<void> _discardQuiz() async {
    await SessionStore.clear();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Тренажёр викторин'),
        actions: [
          IconButton(
            tooltip: 'История попыток',
            icon: const Icon(Icons.history),
            onPressed: () => _open(HistoryScreen(repo: _repo)),
          ),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: Text('Импорт Excel')),
              PopupMenuItem(
                value: 'export',
                child: Text('Экспорт базы (JSON)'),
              ),
              PopupMenuItem(
                value: 'restore',
                child: Text('Импорт базы (JSON)'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addGroup,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('Группа'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                if (_active != null) _activeCard(_active!),
                if (_groups.isEmpty)
                  EmptyState(
                    icon: Icons.quiz_outlined,
                    text:
                        'Пока нет вопросов.\nСоздайте группу или импортируйте Excel-файлы — '
                        'каждый файл станет отдельной компетенцией.',
                    actions: [
                      FilledButton.icon(
                        onPressed: _importExcel,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Импорт Excel'),
                      ),
                      OutlinedButton(
                        onPressed: () => _menu('restore'),
                        child: const Text('Импорт базы (JSON)'),
                      ),
                    ],
                  ),
                for (final g in _groups) _groupTile(g),
              ],
            ),
    );
  }

  Widget _groupTile(Group g) {
    final comps = _competencies.where((c) => c.groupId == g.id).toList();
    final questions = comps.fold(0, (sum, c) => sum + (_counts[c.id] ?? 0));
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.folder_outlined)),
      title: Text(g.name),
      subtitle: Text(
        '${plural(comps.length, 'компетенция', 'компетенции', 'компетенций')} · '
        '${questionsLabel(questions)}',
      ),
      trailing: ItemMenu(
        onRename: () => _rename(g),
        onDelete: () => _delete(g),
      ),
      onTap: () => _open(GroupScreen(repo: _repo, group: g)),
    );
  }

  Widget _activeCard(QuizSession s) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: ListTile(
        leading: const Icon(Icons.play_circle_outline),
        title: Text('Незавершённый тест: ${s.title}'),
        subtitle: Text('${s.mode} · вопрос ${s.index + 1} из ${s.total}'),
        onTap: () => _continueQuiz(s),
        trailing: IconButton(
          tooltip: 'Сбросить',
          icon: const Icon(Icons.close),
          onPressed: _discardQuiz,
        ),
      ),
    );
  }
}
