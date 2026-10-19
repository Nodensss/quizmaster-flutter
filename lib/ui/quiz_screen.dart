import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../quiz/quiz_session.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.repo, required this.session});

  final QuizRepository repo;
  final QuizSession session;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late QuizSession _s = widget.session;

  void _update(VoidCallback change) {
    setState(change);
    unawaited(SessionStore.save(_s));
  }

  void _select(int option) => _update(() => _s.pending = option);

  void _check() {
    final selected = _s.pending;
    if (selected == null || _s.isChecked) return;
    final item = _s.current;
    _update(() {
      _s.answers[_s.index] = selected;
      _s.pending = null;
    });
    if (item.questionId != null) {
      unawaited(
        widget.repo.recordAnswer(
          item.questionId!,
          item.options[selected].correct,
        ),
      );
    }
  }

  void _back() {
    if (_s.index == 0) return;
    _update(() {
      _s.index--;
      _s.pending = null;
    });
  }

  Future<void> _next() async {
    _update(() {
      _s.index++;
      _s.pending = null;
    });
    if (_s.isFinished && !_s.saved) {
      _s.saved = true;
      await widget.repo.addAttempt(
        title: _s.title,
        mode: _s.mode,
        total: _s.total,
        score: _s.score,
      );
      await SessionStore.clear();
    }
  }

  void _retryMistakes() {
    final next = _s.retryMistakes();
    setState(() => _s = next);
    unawaited(SessionStore.save(next));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(_s.mode, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      body: SafeArea(child: _s.isFinished ? _result() : _question()),
    );
  }

  Widget _question() {
    final item = _s.current;
    final answer = _s.currentAnswer;
    final chosen = answer ?? _s.pending;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        LinearProgressIndicator(value: (_s.index + 1) / _s.total),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Вопрос ${_s.index + 1} из ${_s.total}'
                '${item.source.isEmpty ? '' : ' · ${item.source}'}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Text(item.text, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              for (var i = 0; i < item.options.length; i++)
                _OptionTile(
                  text: item.options[i].text,
                  selected: chosen == i,
                  state: answer == null
                      ? _OptionState.open
                      : item.options[i].correct
                      ? _OptionState.correct
                      : answer == i
                      ? _OptionState.wrong
                      : _OptionState.idle,
                  onTap: answer == null ? () => _select(i) : null,
                ),
              if (answer != null) ...[
                const SizedBox(height: 8),
                Text(
                  item.options[answer].correct
                      ? 'Верно!'
                      : 'Неверно. Правильный ответ: ${item.correct}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: item.options[answer].correct
                        ? Colors.green.shade700
                        : scheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: _s.index > 0 ? _back : null,
                child: const Text('Назад'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: answer == null
                    ? FilledButton(
                        onPressed: _s.pending == null ? null : _check,
                        child: const Text('Проверить'),
                      )
                    : FilledButton(
                        onPressed: _next,
                        child: Text(
                          _s.index + 1 == _s.total ? 'Завершить' : 'Далее',
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _result() {
    final total = _s.total;
    final score = _s.score;
    final pct = total == 0 ? 0.0 : score / total * 100;
    final wrong = _s.wrongIndexes;
    final verdict = pct >= 90
        ? 'Отличный результат!'
        : pct >= 70
        ? 'Хороший результат.'
        : pct >= 50
        ? 'Неплохо, стоит повторить темы.'
        : 'Нужно ещё потренироваться.';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Результат', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          '$score из $total (${pct.toStringAsFixed(1)}%)',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(verdict),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Готово'),
            ),
            if (wrong.isNotEmpty)
              OutlinedButton(
                onPressed: _retryMistakes,
                child: Text('Работа над ошибками (${wrong.length})'),
              ),
          ],
        ),
        if (wrong.isNotEmpty) ...[
          const SizedBox(height: 16),
          ExpansionTile(
            title: Text('Разбор ошибок (${wrong.length})'),
            children: [
              for (final i in wrong)
                ListTile(
                  title: Text(_s.items[i].text),
                  subtitle: Text(
                    'Ваш ответ: ${_s.items[i].options[_s.answers[i]!].text}\n'
                    'Правильный: ${_s.items[i].correct}'
                    '${_s.items[i].source.isEmpty ? '' : '\n${_s.items[i].source}'}',
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

enum _OptionState { open, idle, correct, wrong }

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.text,
    required this.selected,
    required this.state,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final _OptionState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color? background, Color border, IconData icon) = switch (state) {
      _OptionState.correct => (
        Colors.green.withValues(alpha: 0.12),
        Colors.green.shade600,
        Icons.check_circle,
      ),
      _OptionState.wrong => (scheme.errorContainer, scheme.error, Icons.cancel),
      _ when selected => (
        scheme.primaryContainer,
        scheme.primary,
        Icons.radio_button_checked,
      ),
      _ => (null, scheme.outlineVariant, Icons.radio_button_unchecked),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: background ?? Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon, color: border),
                const SizedBox(width: 12),
                Expanded(child: Text(text)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
