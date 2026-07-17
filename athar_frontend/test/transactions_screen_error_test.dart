import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:athar/models/models.dart';
import 'package:athar/screens/transactions_screen.dart';
import 'package:athar/services/api_service.dart';
import 'package:athar/widgets/common_widgets.dart';

/// Fake ApiService whose getTransactionHistory can be told to fail or succeed.
/// Only overrides the endpoint TransactionsScreen touches on first build.
class FakeTransactionsApi extends ApiService {
  FakeTransactionsApi() : super(baseUrl: 'http://unused.test');

  bool fail = false;
  int calls = 0;
  List<TransactionHistoryItem> items = [];

  @override
  Future<List<TransactionHistoryItem>> getTransactionHistory(String userId) async {
    calls++;
    if (fail) throw ApiException(503, 'backend down');
    return items;
  }
}

Widget _wrap(FakeTransactionsApi api) => MaterialApp(
      home: TransactionsScreen(userId: 'user-1', api: api),
    );

Future<void> _pump(WidgetTester tester, FakeTransactionsApi api) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(api));
  await tester.pump(); // let futures complete
  await tester.pump();
}

TransactionHistoryItem _item() => TransactionHistoryItem(
      id: 't1',
      description: 'بقالة',
      amount: 120,
      category: AppCategory.groceries,
      type: 'EXPENSE',
      createdAt: DateTime(2026, 6, 1, 10, 0),
    );

void main() {
  testWidgets('API error shows ErrorRetryView', (tester) async {
    final api = FakeTransactionsApi()..fail = true;
    await _pump(tester, api);

    expect(find.byType(ErrorRetryView), findsOneWidget);
    // Neither transaction data nor empty-state message should show.
    expect(find.text('لا توجد معاملات بعد'), findsNothing);
  });

  testWidgets('retry after error recovers and shows transactions', (tester) async {
    final api = FakeTransactionsApi()
      ..fail = true
      ..items = [_item()];
    await _pump(tester, api);

    expect(find.byType(ErrorRetryView), findsOneWidget);

    // Flip to success and press retry.
    api.fail = false;
    final callsBefore = api.calls;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pump();
    await tester.pump();

    expect(api.calls, greaterThan(callsBefore));
    expect(find.byType(ErrorRetryView), findsNothing);
    expect(find.text('بقالة'), findsOneWidget);
  });

  testWidgets('retry after error with empty list shows empty state',
      (tester) async {
    final api = FakeTransactionsApi()..fail = true;
    await _pump(tester, api);

    expect(find.byType(ErrorRetryView), findsOneWidget);

    api.fail = false;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(ErrorRetryView), findsNothing);
    expect(find.text('لا توجد معاملات بعد'), findsOneWidget);
  });

  testWidgets('successful load with items shows them without ErrorRetryView',
      (tester) async {
    final api = FakeTransactionsApi()..items = [_item()];
    await _pump(tester, api);

    expect(find.byType(ErrorRetryView), findsNothing);
    expect(find.text('بقالة'), findsOneWidget);
  });

  testWidgets('successful load with no items shows empty state',
      (tester) async {
    final api = FakeTransactionsApi();
    await _pump(tester, api);

    expect(find.byType(ErrorRetryView), findsNothing);
    expect(find.text('لا توجد معاملات بعد'), findsOneWidget);
  });
}
