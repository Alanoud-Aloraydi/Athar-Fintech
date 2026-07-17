import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:athar/models/models.dart';
import 'package:athar/screens/dashboard_screen.dart';
import 'package:athar/services/api_service.dart';
import 'package:athar/widgets/common_widgets.dart';

/// Fake ApiService whose getDashboardSummary can be told to fail or succeed.
/// Only overrides the endpoint DashboardScreen touches on first build.
class FakeDashboardApi extends ApiService {
  FakeDashboardApi() : super(baseUrl: 'http://unused.test');

  bool fail = false;
  int calls = 0;

  @override
  Future<DashboardSummary> getDashboardSummary(String userId) async {
    calls++;
    if (fail) throw ApiException(503, 'backend down');
    return DashboardSummary(
      userId: userId,
      currentBalance: 1500,
      totalIncome: 3000,
      totalExpenses: 1500,
      netFlow: 1500,
      activeGoal: null,
      spendingByCategory: const [],
      oasisGrowthScore: 4.2,
      oasisHealthScore: 75,
      insights: SmartInsights(
        spendingVelocityPerDay: 50,
        projectedGoalCompletionDate: null,
        trajectoryMessage: 'على المسار الصحيح',
      ),
    );
  }
}

Widget _wrap(FakeDashboardApi api) => MaterialApp(
      home: DashboardScreen(userId: 'user-1', api: api),
    );

Future<void> _pump(WidgetTester tester, FakeDashboardApi api) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // DashboardScreen uses Arabic DateFormat, so locale data must be loaded.
  await initializeDateFormatting('ar', null);
  await tester.pumpWidget(_wrap(api));
  await tester.pump(); // let futures complete
  await tester.pump();
}

void main() {
  // DashboardScreen builds a DateFormat with the 'ar' locale; its symbol
  // data must be loaded before the widget is constructed.
  setUpAll(() => initializeDateFormatting('ar'));

  testWidgets('API error shows ErrorRetryView', (tester) async {
    final api = FakeDashboardApi()..fail = true;
    await _pump(tester, api);

    expect(find.byType(ErrorRetryView), findsOneWidget);
    // Data content must not be rendered.
    expect(find.text('الرصيد الإجمالي'), findsNothing);
  });

  testWidgets('retry after error recovers and shows data', (tester) async {
    final api = FakeDashboardApi()..fail = true;
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
    expect(find.text('الرصيد الإجمالي'), findsOneWidget);
  });

  testWidgets('successful load shows balance summary without ErrorRetryView',
      (tester) async {
    final api = FakeDashboardApi();
    await _pump(tester, api);

    expect(find.byType(ErrorRetryView), findsNothing);
    expect(find.text('الرصيد الإجمالي'), findsOneWidget);
  });
}
