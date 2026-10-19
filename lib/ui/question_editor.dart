import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../data/text_utils.dart';
import 'common.dart';

/// Создание и редактирование вопроса. Возвращает `true`, если что-то изменилось.
class QuestionEditor extends StatefulWidget {
  const QuestionEditor({
    super.key,
    required this.repo,
    required this.competencyId,
    this.question,
  });

  final QuizRepository repo;
  final int competencyId;
  final Question? question;

  @override
  State<QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<QuestionEditor> {
  final _form = GlobalKey<FormState>();
  late final _text = TextEditingController(text: widget.question?.text);
  late final _correct = TextEditingController(text: widget.question?.correct);
  late final List<TextEditingController> _wrong = [
    for (final w in widget.question?.wrong ?? const ['', '', ''])
      TextEditingController(text: w),
  ];
  var _saving = false;

  bool get _isNew => widget.question == null;

  @override
  void dispose() {
    for (final c in [_text, _correct, ..._wrong]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final wrong = [
      for (final c in _wrong)
        if (c.text.trim().isNotEmpty) c.text.trim(),
    ];
    if (wrong.isEmpty) {
      toast(context, 'Нужен хотя бы один неправильный ответ.');
      return;
    }
    final draft = QuestionDraft(
      text: _text.text.trim(),
      correct: _correct.text.trim(),
      wrong: wrong,
    );
    setState(() => _saving = true);
    if (_isNew) {
      await widget.repo.addQuestion(widget.competencyId, draft);
    } else {
      await widget.repo.updateQuestion(
        widget.question!.id,
        widget.question!.competencyId,
        draft,
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Удалить вопрос?',
      message: widget.question!.text,
    );
    if (!ok) return;
    await widget.repo.deleteQuestion(widget.question!.id);
    if (mounted) Navigator.pop(context, true);
  }

  void _removeWrong(int i) {
    final removed = _wrong[i];
    setState(() => _wrong.removeAt(i));
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  String? _required(String? v) =>
      (v ?? '').trim().isEmpty ? 'Заполните поле' : null;

  String? _notCorrect(String? v) {
    final t = (v ?? '').trim();
    if (t.isNotEmpty && normalizeText(t) == normalizeText(_correct.text)) {
      return 'Совпадает с правильным ответом';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Новый вопрос' : 'Вопрос'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Удалить',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _text,
              autofocus: _isNew,
              minLines: 2,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Вопрос',
                border: OutlineInputBorder(),
              ),
              validator: _required,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _correct,
              maxLines: null,
              decoration: InputDecoration(
                labelText: 'Правильный ответ',
                border: const OutlineInputBorder(),
                prefixIcon: Icon(Icons.check, color: Colors.green.shade600),
              ),
              validator: _required,
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < _wrong.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: _wrong[i],
                  maxLines: null,
                  decoration: InputDecoration(
                    labelText: 'Неправильный ответ ${i + 1}',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(
                      Icons.close,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    suffixIcon: _wrong.length > 1
                        ? IconButton(
                            tooltip: 'Убрать',
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => _removeWrong(i),
                          )
                        : null,
                  ),
                  validator: _notCorrect,
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _wrong.add(TextEditingController())),
                icon: const Icon(Icons.add),
                label: const Text('Добавить неправильный ответ'),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}
