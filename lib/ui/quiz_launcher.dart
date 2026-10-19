import 'dart:math';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../quiz/quiz_session.dart';
import 'common.dart';
import 'quiz_screen.dart';

/// Спрашивает количество вопросов, собирает тест и открывает его.
/// Завершается, когда пользователь закрывает экран теста.
Future<void> startQuiz(
  BuildContext context,
  QuizRepository repo, {
  required String title,
  required List<Question> pool,
  required Map<int, String> sources,
  String mode = modeMain,
}) async {
  if (pool.isEmpty) {
    toast(context, 'Нет вопросов для теста.');
    return;
  }
  var count = pool.length;
  if (pool.length > 1) {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => _CountSheet(
        title: title,
        max: pool.length,
        initial: mode == modeMistakes ? pool.length : min(20, pool.length),
      ),
    );
    if (picked == null) return;
    count = picked;
  }

  final session = QuizSession.fromQuestions(
    pool: pool,
    count: count,
    sources: sources,
    title: title,
    mode: mode,
  );
  if (session.total == 0) {
    if (context.mounted) toast(context, 'Не удалось собрать вопросы.');
    return;
  }
  await SessionStore.save(session);
  if (!context.mounted) return;
  await openQuiz(context, repo, session);
}

Future<void> openQuiz(
  BuildContext context,
  QuizRepository repo,
  QuizSession session,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => QuizScreen(repo: repo, session: session),
  ),
);

class _CountSheet extends StatefulWidget {
  const _CountSheet({
    required this.title,
    required this.max,
    required this.initial,
  });

  final String title;
  final int max;
  final int initial;

  @override
  State<_CountSheet> createState() => _CountSheetState();
}

class _CountSheetState extends State<_CountSheet> {
  late int _count = widget.initial;

  @override
  Widget build(BuildContext context) {
    final presets = {10, 20, 50}.where((n) => n < widget.max).toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Количество вопросов: $_count из ${widget.max}'),
            Slider(
              value: _count.toDouble(),
              min: 1,
              max: widget.max.toDouble(),
              divisions: widget.max - 1,
              label: '$_count',
              onChanged: (v) => setState(() => _count = v.round()),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final n in presets)
                  ChoiceChip(
                    label: Text('$n'),
                    selected: _count == n,
                    onSelected: (_) => setState(() => _count = n),
                  ),
                ChoiceChip(
                  label: const Text('Все'),
                  selected: _count == widget.max,
                  onSelected: (_) => setState(() => _count = widget.max),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, _count),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Начать'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
