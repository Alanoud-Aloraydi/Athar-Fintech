import 'package:flutter_test/flutter_test.dart';
import 'package:athar/main.dart';

void main() {
  testWidgets('App builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const AtharApp());
    expect(find.byType(AtharApp), findsOneWidget);
  });
}
