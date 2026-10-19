import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'common.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.repo});

  final QuizRepository repo;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Attempt>? _attempts;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final attempts = await widget.repo.attempts();
    if (mounted) setState(() => _attempts = attempts);
  }

  Future<void> _clear() async {
    final ok = await confirm(
      context,
      title: 'Очистить историю?',
      message: 'Все записи о пройденных тестах будут удалены.',
      action: 'Очистить',
    );
    if (!ok) return;
    await widget.repo.clearAttempts();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final attempts = _attempts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('История попыток'),
        actions: [
          if (attempts != null && attempts.isNotEmpty)
            IconButton(
              tooltip: 'Очистить',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clear,
            ),
        ],
      ),
      body: attempts == null
          ? const Center(child: CircularProgressIndicator())
          : attempts.isEmpty
          ? const EmptyState(
              icon: Icons.history,
              text: 'Пока нет завершённых тестов.',
            )
          : ListView.separated(
              itemCount: attempts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final a = attempts[i];
                return ListTile(
                  title: Text(a.title),
                  subtitle: Text('${a.mode} · ${formatDateTime(a.time)}'),
                  trailing: Text(
                    '${a.score}/${a.total}\n${a.percent.toStringAsFixed(0)}%',
                    textAlign: TextAlign.end,
                  ),
                );
              },
            ),
    );
  }
}
