import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/repository.dart';
import 'ui/home_screen.dart';

/// Встроенные вопросы: экспорт базы, положенный в assets перед сборкой.
const seedAsset = 'assets/seed/questions.json';

void main() => runApp(const QuizApp());

Future<QuizRepository> openAppRepository() async {
  final repo = await QuizRepository.open();
  try {
    final json = jsonDecode(await rootBundle.loadString(seedAsset)) as Map;
    await repo.applySeed(json.cast<String, Object?>());
  } catch (e) {
    debugPrint('Встроенные вопросы не загружены: $e');
  }
  return repo;
}

class QuizApp extends StatelessWidget {
  const QuizApp({super.key, this.openRepository = openAppRepository});

  final Future<QuizRepository> Function() openRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Тренажёр викторин',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFCC2D2D)),
        useMaterial3: true,
      ),
      home: _Startup(openRepository),
    );
  }
}

class _Startup extends StatefulWidget {
  const _Startup(this.open);

  final Future<QuizRepository> Function() open;

  @override
  State<_Startup> createState() => _StartupState();
}

class _StartupState extends State<_Startup> {
  late final Future<QuizRepository> _repo = widget.open();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _repo,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Не удалось открыть базу: ${snapshot.error}'),
              ),
            ),
          );
        }
        final repo = snapshot.data;
        if (repo == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return HomeScreen(repo: repo);
      },
    );
  }
}
