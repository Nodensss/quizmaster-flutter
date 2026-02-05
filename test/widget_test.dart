import 'package:flutter_test/flutter_test.dart';
import 'package:quizmaster_flutter/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app starts and shows upload button', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const QuizApp());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Выбрать Excel файлы'), findsOneWidget);
  });
}
