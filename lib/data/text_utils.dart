String normalizeText(String s) =>
    s.trim().toLowerCase().replaceAll('ё', 'е').replaceAll(RegExp(r'\s+'), ' ');

String normalizeHeader(String s) =>
    normalizeText(s).replaceAll(RegExp(r'[^a-zа-я0-9]+'), '');

/// Ключ, по которому повторный импорт распознаёт уже существующий вопрос.
String questionKey(String text, String correct) =>
    '${normalizeText(text)}\u0000${normalizeText(correct)}';

String fileLabel(String name) {
  final t = name.trim();
  final dot = t.lastIndexOf('.');
  if (dot <= 0) return t;
  final ext = t.substring(dot + 1).toLowerCase();
  if (ext == 'xlsx' || ext == 'xls') return t.substring(0, dot);
  return t;
}

int compareNames(String a, String b) =>
    a.toLowerCase().compareTo(b.toLowerCase());
