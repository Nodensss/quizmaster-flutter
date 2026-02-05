// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _all = '__all__';
const _sessionKey = 'quizmaster_flutter_session_v1';
const _historyKey = 'quizmaster_flutter_history_v1';
const _required = ['question', 'correct', 'wrong1', 'wrong2', 'wrong3'];
const _aliases = {
  'question': ['Вопрос', 'Question', 'Текст вопроса'],
  'correct': ['Правильный ответ', 'Верный ответ', 'Correct answer'],
  'wrong1': ['Неправильный ответ 1', 'Неверный ответ 1', 'Wrong answer 1'],
  'wrong2': ['Неправильный ответ 2', 'Неверный ответ 2', 'Wrong answer 2'],
  'wrong3': ['Неправильный ответ 3', 'Неверный ответ 3', 'Wrong answer 3'],
};

void main() => runApp(const QuizApp());

class QuizApp extends StatelessWidget {
  const QuizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Тренажер викторин',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFCC2D2D)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _rng = Random();

  var _restoring = true;
  var _loadingFiles = false;

  List<Map<String, dynamic>> _rows = [];
  List<String> _files = [];
  List<String> _warnings = [];
  String _selectedFile = _all;
  int _quizCount = 20;

  var _quizStarted = false;
  List<Map<String, dynamic>> _questions = [];
  int _index = 0;
  int _score = 0;
  bool _checked = false;
  bool _lastCorrect = false;
  int? _selectedOption;
  List<Map<String, dynamic>> _wrong = [];
  String _mode = 'Основная викторина';
  String _selectionLabel = 'Все файлы';
  List<String> _sessionFiles = [];
  bool _attemptSaved = false;

  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();

    final h = prefs.getString(_historyKey);
    if (h != null && h.isNotEmpty) {
      try {
        final d = jsonDecode(h);
        if (d is List) {
          _history = d
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {
        _history = [];
      }
    }

    final s = prefs.getString(_sessionKey);
    if (s != null && s.isNotEmpty) {
      try {
        final d = jsonDecode(s);
        if (d is Map) {
          final m = Map<String, dynamic>.from(d);
          final qs =
              (m['questions'] as List?)
                  ?.whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList() ??
              [];
          if (qs.isNotEmpty) {
            _quizStarted = true;
            _questions = qs;
            _index = _clamp(_asInt(m['index'], 0), 0, qs.length);
            _score = _clamp(_asInt(m['score'], 0), 0, qs.length);
            _checked = _asBool(m['checked'], false);
            _lastCorrect = _asBool(m['lastCorrect'], false);
            _selectedOption = _asIntN(m['selectedOption']);
            _wrong =
                (m['wrong'] as List?)
                    ?.whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList() ??
                [];
            _mode = _asStr(m['mode'], 'Основная викторина');
            _selectionLabel = _asStr(m['selectionLabel'], 'Все файлы');
            _sessionFiles =
                (m['sessionFiles'] as List?)?.map((e) => '$e').toList() ?? [];
            _attemptSaved = _asBool(m['attemptSaved'], false);
          }
        }
      } catch (_) {
        _quizStarted = false;
      }
    }

    if (!mounted) return;
    setState(() => _restoring = false);
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_historyKey, jsonEncode(_history));
  }

  Future<void> _saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_quizStarted || _questions.isEmpty) {
      await prefs.remove(_sessionKey);
      return;
    }
    final m = {
      'questions': _questions,
      'index': _index,
      'score': _score,
      'checked': _checked,
      'lastCorrect': _lastCorrect,
      'selectedOption': _selectedOption,
      'wrong': _wrong,
      'mode': _mode,
      'selectionLabel': _selectionLabel,
      'sessionFiles': _sessionFiles,
      'attemptSaved': _attemptSaved,
    };
    await prefs.setString(_sessionKey, jsonEncode(m));
  }

  List<Map<String, dynamic>> _pool() {
    if (_selectedFile == _all) return _rows;
    return _rows.where((r) => r['file'] == _selectedFile).toList();
  }

  Future<void> _pickFiles() async {
    if (_loadingFiles) return;
    setState(() => _loadingFiles = true);

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xls'],
        withData: true,
      );
    } catch (_) {
      _toast('Не удалось открыть выбор файлов.');
    }

    if (!mounted) return;
    if (result == null || result.files.isEmpty) {
      setState(() => _loadingFiles = false);
      return;
    }

    final parsed = <Map<String, dynamic>>[];
    final notes = <String>[];

    for (final f in result.files) {
      parsed.addAll(_parseFile(f, notes));
    }

    final files = parsed.map((e) => '${e['file']}').toSet().toList()..sort();

    setState(() {
      _rows = parsed;
      _files = files;
      _warnings = notes;
      _selectedFile = _all;
      _quizCount = parsed.isEmpty ? 20 : min(20, parsed.length);
      _resetQuiz();
      _loadingFiles = false;
    });

    unawaited(_saveSession());
    _toast(
      parsed.isEmpty
          ? 'Валидные вопросы не найдены.'
          : 'Загружено: ${parsed.length} вопросов.',
    );
  }

  List<Map<String, dynamic>> _parseFile(PlatformFile f, List<String> notes) {
    final out = <Map<String, dynamic>>[];
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) {
      notes.add('${f.name}: не удалось прочитать файл.');
      return out;
    }

    late final Excel wb;
    try {
      wb = Excel.decodeBytes(bytes);
    } catch (_) {
      notes.add('${f.name}: неверный формат/поврежденный файл.');
      return out;
    }

    if (wb.tables.isEmpty) {
      notes.add('${f.name}: нет листов с данными.');
      return out;
    }

    final sheet = wb.tables[wb.tables.keys.first];
    if (sheet == null || sheet.rows.isEmpty) {
      notes.add('${f.name}: лист пустой.');
      return out;
    }

    final header = sheet.rows.first.map(_cell).toList();
    final res = _resolve(header);
    if (res['unresolved'].isNotEmpty) {
      notes.add(
        '${f.name}: не найдены колонки (${(res['unresolved'] as List).join(', ')}).',
      );
      return out;
    }
    if (res['fallback'] == true) {
      notes.add('${f.name}: имена не совпали, использованы первые 5 колонок.');
    }

    final m = Map<String, int>.from(res['map']);
    for (final r in sheet.rows.skip(1)) {
      final q = _read(r, m, 'question');
      final c = _read(r, m, 'correct');
      if (q.isEmpty || c.isEmpty) continue;

      final wrongs = <String>[];
      final seen = <String>{};
      for (final k in ['wrong1', 'wrong2', 'wrong3']) {
        final v = _read(r, m, k);
        if (v.isEmpty) continue;
        if (_norm(v) == _norm(c)) continue;
        if (seen.add(_norm(v))) wrongs.add(v);
      }
      if (wrongs.isEmpty) continue;

      out.add({'q': q, 'c': c, 'w': wrongs, 'file': f.name});
    }

    if (out.isEmpty) {
      notes.add('${f.name}: после очистки не осталось валидных строк.');
    }
    return out;
  }

  String _read(List<dynamic> row, Map<String, int> map, String key) {
    final i = map[key];
    if (i == null || i < 0 || i >= row.length) return '';
    return _cell(row[i]);
  }

  Map<String, dynamic> _resolve(List<String> headers) {
    final idx = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      idx.putIfAbsent(_normHeader(headers[i]), () => i);
    }

    final map = <String, int>{};
    final unresolved = <String>[];
    for (final field in _required) {
      int? found;
      for (final a in (_aliases[field] ?? const <String>[])) {
        final i = idx[_normHeader(a)];
        if (i != null) {
          found = i;
          break;
        }
      }
      if (found == null) {
        unresolved.add(field);
      } else {
        map[field] = found;
      }
    }

    var fallback = false;
    if (unresolved.isNotEmpty && headers.length >= _required.length) {
      fallback = true;
      for (var i = 0; i < _required.length; i++) {
        map.putIfAbsent(_required[i], () => i);
      }
      unresolved.clear();
    }

    return {'map': map, 'unresolved': unresolved, 'fallback': fallback};
  }

  void _startQuiz() {
    final pool = _pool();
    if (pool.isEmpty) {
      _toast('Нет вопросов для выбранного файла.');
      return;
    }

    final qs = _buildQuestions(pool, _quizCount);
    if (qs.isEmpty) {
      _toast('Не удалось собрать вопросы.');
      return;
    }

    final files = qs.map((e) => '${e['file']}').toSet().toList()..sort();
    setState(() {
      _quizStarted = true;
      _questions = qs;
      _index = 0;
      _score = 0;
      _checked = false;
      _lastCorrect = false;
      _selectedOption = null;
      _wrong = [];
      _mode = 'Основная викторина';
      _selectionLabel = _selectedFile == _all
          ? 'Все файлы'
          : _fileLabel(_selectedFile);
      _sessionFiles = files;
      _attemptSaved = false;
    });
    unawaited(_saveSession());
  }

  List<Map<String, dynamic>> _buildQuestions(
    List<Map<String, dynamic>> pool,
    int count,
  ) {
    final shuffled = List<Map<String, dynamic>>.from(pool)..shuffle(_rng);
    final out = <Map<String, dynamic>>[];

    for (final r in shuffled.take(count)) {
      final opts = <Map<String, dynamic>>[];
      final seen = <String>{};

      void add(String t, bool ok) {
        final s = t.trim();
        if (s.isEmpty) return;
        if (seen.add(_norm(s))) opts.add({'t': s, 'ok': ok});
      }

      add('${r['c']}', true);
      for (final w in (r['w'] as List)) {
        add('$w', false);
      }
      if (opts.length < 2) continue;
      opts.shuffle(_rng);

      out.add({'q': r['q'], 'c': r['c'], 'file': r['file'], 'opts': opts});
    }
    return out;
  }

  void _check() {
    if (!_quizStarted || _checked || _selectedOption == null) return;
    final q = _questions[_index];
    final opt = (q['opts'] as List)[_selectedOption!] as Map;
    final ok = opt['ok'] == true;

    setState(() {
      _checked = true;
      _lastCorrect = ok;
      if (ok) {
        _score++;
      } else {
        _wrong.add({'question': q, 'selected': '${opt['t']}'});
      }
    });
    unawaited(_saveSession());
  }

  void _next() {
    if (!_quizStarted || !_checked) return;
    setState(() {
      _index++;
      _checked = false;
      _lastCorrect = false;
      _selectedOption = null;
      if (_index >= _questions.length) _registerAttempt();
    });
    unawaited(_saveSession());
    unawaited(_saveHistory());
  }

  void _registerAttempt() {
    if (_attemptSaved || _questions.isEmpty) return;
    final total = _questions.length;
    final percent = total == 0 ? 0.0 : (_score / total) * 100.0;
    _history.insert(0, {
      'time': DateTime.now().toString().split('.').first,
      'mode': _mode,
      'selection': _selectionLabel,
      'total': total,
      'score': _score,
      'errors': max(total - _score, 0),
      'percent': percent,
      'files': _sessionFiles.map(_fileLabel).toList(),
    });
    _attemptSaved = true;
  }

  void _trainMistakes() {
    if (_wrong.isEmpty) {
      _toast('Нет ошибок для тренировки.');
      return;
    }
    final qs = _wrong.map((e) {
      final q = Map<String, dynamic>.from(e['question']);
      final opts =
          (q['opts'] as List).map((x) => Map<String, dynamic>.from(x)).toList()
            ..shuffle(_rng);
      q['opts'] = opts;
      return q;
    }).toList()..shuffle(_rng);

    setState(() {
      _quizStarted = true;
      _questions = qs;
      _index = 0;
      _score = 0;
      _checked = false;
      _lastCorrect = false;
      _selectedOption = null;
      _wrong = [];
      _mode = 'Тренировка ошибок';
      _attemptSaved = false;
    });
    unawaited(_saveSession());
  }

  void _resetQuiz() {
    _quizStarted = false;
    _questions = [];
    _index = 0;
    _score = 0;
    _checked = false;
    _lastCorrect = false;
    _selectedOption = null;
    _wrong = [];
    _mode = 'Основная викторина';
    _selectionLabel = 'Все файлы';
    _sessionFiles = [];
    _attemptSaved = false;
  }

  void _newQuiz() {
    setState(_resetQuiz);
    unawaited(_saveSession());
  }

  void _clearHistory() {
    setState(() => _history = []);
    unawaited(_saveHistory());
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pool = _pool();
    final poolSize = pool.length;
    final count = poolSize == 0 ? 0 : _clamp(_quizCount, 1, poolSize);

    return Scaffold(
      appBar: AppBar(title: const Text('Тренажер викторин')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _importCard(),
              const SizedBox(height: 16),
              if (!_quizStarted) _setupCard(poolSize, count),
              if (_quizStarted) _quizCard(),
              const SizedBox(height: 16),
              _historyCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _importCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1) Загрузка Excel файлов',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadingFiles ? null : _pickFiles,
              icon: const Icon(Icons.upload_file),
              label: const Text('Выбрать Excel файлы'),
            ),
            if (_loadingFiles) ...const [
              SizedBox(height: 12),
              LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            Text('Загружено валидных вопросов: ${_rows.length}'),
            if (_files.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _files
                    .map((f) => Chip(label: Text(_fileLabel(f))))
                    .toList(),
              ),
            ],
            if (_warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _warnings.map((w) => Text('• $w')).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _setupCard(int poolSize, int count) {
    if (_rows.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Загрузите файлы, чтобы начать.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '2) Настройка викторины',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedFile,
              decoration: const InputDecoration(
                labelText: 'Выберите файл (как компетенцию)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: _all, child: Text('Все файлы')),
                ..._files.map(
                  (f) => DropdownMenuItem(value: f, child: Text(_fileLabel(f))),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                final s = v == _all
                    ? _rows.length
                    : _rows.where((r) => r['file'] == v).length;
                setState(() {
                  _selectedFile = v;
                  if (s > 0) _quizCount = _clamp(_quizCount, 1, s);
                });
              },
            ),
            const SizedBox(height: 12),
            Text('В выбранной выборке: $poolSize вопросов'),
            const SizedBox(height: 8),
            Text('Количество вопросов: $count'),
            if (poolSize > 1)
              Slider(
                value: count.toDouble(),
                min: 1,
                max: poolSize.toDouble(),
                divisions: poolSize - 1,
                label: '$count',
                onChanged: (v) =>
                    setState(() => _quizCount = _clamp(v.round(), 1, poolSize)),
              ),
            if (poolSize <= 1) const SizedBox(height: 12),
            FilledButton(
              onPressed: poolSize == 0 ? null : _startQuiz,
              child: const Text('Начать викторину'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quizCard() {
    if (_index >= _questions.length) return _resultCard();

    final q = _questions[_index];
    final opts = q['opts'] as List;
    final progress = _questions.isEmpty
        ? 0.0
        : (_index + 1) / _questions.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Режим: $_mode | Выборка: $_selectionLabel',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text('Вопрос ${_index + 1} из ${_questions.length}'),
            const SizedBox(height: 8),
            Text(
              'Файл: ${_fileLabel('${q['file']}')}',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            Text(
              '${q['q']}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ...List.generate(opts.length, (i) {
              final o = opts[i] as Map;
              return RadioListTile<int>(
                value: i,
                groupValue: _selectedOption,
                onChanged: _checked
                    ? null
                    : (v) {
                        setState(() => _selectedOption = v);
                        unawaited(_saveSession());
                      },
                title: Text('${o['t']}'),
              );
            }),
            const SizedBox(height: 12),
            if (!_checked)
              FilledButton(
                onPressed: _selectedOption == null ? null : _check,
                child: const Text('Проверить ответ'),
              ),
            if (_checked) ...[
              Text(
                _lastCorrect
                    ? 'Верно!'
                    : 'Неверно. Правильный ответ: ${q['c']}',
                style: TextStyle(
                  color: _lastCorrect
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _next,
                child: Text(
                  _index + 1 == _questions.length
                      ? 'Завершить'
                      : 'Следующий вопрос',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultCard() {
    final total = _questions.length;
    final pct = total == 0 ? 0.0 : (_score / total) * 100.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Результат',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('Счет: $_score / $total (${pct.toStringAsFixed(1)}%)'),
            const SizedBox(height: 8),
            if (pct >= 90)
              const Text('Отличный результат!')
            else if (pct >= 70)
              const Text('Хороший результат.')
            else if (pct >= 50)
              const Text('Неплохо, стоит повторить темы.')
            else
              const Text('Нужно еще потренироваться.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _newQuiz,
                  child: const Text('Новая викторина'),
                ),
                OutlinedButton(
                  onPressed: _wrong.isEmpty ? null : _trainMistakes,
                  child: const Text('Тренировать ошибки'),
                ),
              ],
            ),
            if (_wrong.isNotEmpty) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                title: Text('Разбор ошибок (${_wrong.length})'),
                children: _wrong.map((e) {
                  final q = Map<String, dynamic>.from(e['question']);
                  return ListTile(
                    title: Text('${q['q']}'),
                    subtitle: Text(
                      'Ваш ответ: ${e['selected']}\nПравильный: ${q['c']}\nФайл: ${_fileLabel('${q['file']}')}',
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _historyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Статистика попыток',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                if (_history.isNotEmpty)
                  TextButton(
                    onPressed: _clearHistory,
                    child: const Text('Очистить'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_history.isEmpty)
              Text(
                'Пока нет завершенных попыток.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            if (_history.isNotEmpty)
              ..._history.map(
                (h) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${h['mode']} • ${h['selection']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${h['time']}\n${h['score']}/${h['total']} (${(_asDouble(h['percent'], 0)).toStringAsFixed(1)}%)',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _cell(dynamic x) {
  if (x == null) return '';
  try {
    final v = x.value;
    return v == null ? '' : '$v'.trim();
  } catch (_) {
    return '$x'.trim();
  }
}

String _normHeader(String s) {
  final a = s.trim().toLowerCase().replaceAll('ё', 'е');
  return a
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), '');
}

String _norm(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String _fileLabel(String n) {
  final t = n.trim();
  final l = t.toLowerCase();
  if (l.endsWith('.xlsx')) return t.substring(0, t.length - 5);
  if (l.endsWith('.xls')) return t.substring(0, t.length - 4);
  return t;
}

int _clamp(int v, int mn, int mx) {
  if (v < mn) return mn;
  if (v > mx) return mx;
  return v;
}

String _asStr(Object? v, String d) => v == null ? d : '$v';

bool _asBool(Object? v, bool d) {
  if (v is bool) return v;
  if (v is String) {
    if (v.toLowerCase() == 'true') return true;
    if (v.toLowerCase() == 'false') return false;
  }
  return d;
}

int _asInt(Object? v, int d) {
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) return int.tryParse(v) ?? d;
  return d;
}

int? _asIntN(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) return int.tryParse(v);
  return null;
}

double _asDouble(Object? v, double d) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? d;
  return d;
}
