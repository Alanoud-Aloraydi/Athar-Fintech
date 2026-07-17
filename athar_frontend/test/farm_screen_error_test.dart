import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:athar/models/models.dart';
import 'package:athar/screens/farm_screen.dart';
import 'package:athar/services/api_service.dart';
import 'package:athar/widgets/common_widgets.dart';

/// Fake ApiService whose oasis/goal fetches can be told to fail or succeed
/// per call. Overrides only what FarmScreen touches on first build; other
/// endpoints are never hit by these tests.
class FakeApiService extends ApiService {
  FakeApiService() : super(baseUrl: 'http://unused.test');

  bool failOasis = false;
  bool failGoal = false;
  Goal? goal;

  int oasisCalls = 0;
  int goalCalls = 0;

  @override
  Future<OasisState> getOasisState(String userId) async {
    oasisCalls++;
    if (failOasis) throw ApiException(503, 'backend down');
    return OasisState(
      userId: userId,
      growthLevel: 3.5,
      healthScore: 80,
      currentStreakDays: 4,
      longestStreakDays: 9,
      visiblePalmCount: 5,
      environment: OasisEnvironment(
        weatherCondition: 'sunny',
        visualAura: 'flourishing',
        streakMultiplier: 1.25,
        moodMessage: 'واحتك مزدهرة',
      ),
    );
  }

  @override
  Future<Goal?> getActiveGoal(String userId) async {
    goalCalls++;
    if (failGoal) throw ApiException(500, 'boom');
    return goal;
  }
}

Widget _wrap(FakeApiService api) => MaterialApp(
      home: FarmScreen(userId: 'user-1', api: api),
    );

/// Pumps the screen and settles the FutureBuilders. The embedded 3D viewer
/// fails gracefully in tests (no WebView platform), which is expected.
Future<void> _pumpFarm(WidgetTester tester, FakeApiService api) async {
  // Tall viewport so the whole ListView (oasis stats, goal panel,
  // simulator card) is built — ListView skips off-screen children.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(api));
  await tester.pump(); // let futures complete
  await tester.pump();
}

Goal _goal() => Goal(
      id: 'g1',
      userId: 'user-1',
      title: 'رحلة العمرة',
      targetAmount: 1000,
      savedAmount: 250,
      category: AppCategory.values.first,
      deadline: null,
      status: 'ACTIVE',
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  testWidgets('oasis fetch error shows ErrorRetryView; goal panel unaffected',
      (tester) async {
    final api = FakeApiService()
      ..failOasis = true
      ..goal = _goal();
    await _pumpFarm(tester, api);

    expect(find.byType(ErrorRetryView), findsOneWidget);
    // Goal panel still rendered and interactive.
    expect(find.text('هدفك المالي'), findsOneWidget);
    expect(find.textContaining('رحلة العمرة'), findsOneWidget);
    expect(find.text('أرشفة الهدف'), findsOneWidget);
    // Simulator card still present.
    expect(find.text('جرّب معاملة على واحتك'), findsOneWidget);

    // Retry re-triggers both fetches; oasis now succeeds.
    api.failOasis = false;
    final before = api.oasisCalls;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pump();
    await tester.pump();
    expect(api.oasisCalls, greaterThan(before));
    expect(find.byType(ErrorRetryView), findsNothing);
    expect(find.text('مستوى النمو'), findsOneWidget);
  });

  testWidgets('goal fetch error shows ErrorRetryView; oasis stats unaffected',
      (tester) async {
    final api = FakeApiService()..failGoal = true;
    await _pumpFarm(tester, api);

    expect(find.byType(ErrorRetryView), findsOneWidget);
    // Oasis stats still rendered.
    expect(find.text('مستوى النمو'), findsOneWidget);
    expect(find.text('الصحة العامة'), findsOneWidget);
    // The error path must NOT masquerade as "no active goal".
    expect(find.text('إضافة هدف جديد'), findsNothing);
    expect(find.text('جرّب معاملة على واحتك'), findsOneWidget);

    // Retry re-triggers the goal fetch; now succeeds with no active goal.
    api.failGoal = false;
    final before = api.goalCalls;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pump();
    await tester.pump();
    expect(api.goalCalls, greaterThan(before));
    expect(find.byType(ErrorRetryView), findsNothing);
    expect(find.text('إضافة هدف جديد'), findsOneWidget);
  });

  testWidgets('both fetches failing shows two ErrorRetryViews; screen usable',
      (tester) async {
    final api = FakeApiService()
      ..failOasis = true
      ..failGoal = true;
    await _pumpFarm(tester, api);

    expect(find.byType(ErrorRetryView), findsNWidgets(2));
    // Simulator card remains interactive.
    expect(find.text('جرّب معاملة على واحتك'), findsOneWidget);

    // Retrying either button re-triggers both fetches and recovers fully.
    api.failOasis = false;
    api.failGoal = false;
    await tester.tap(find.text('إعادة المحاولة').first);
    await tester.pump();
    await tester.pump();
    expect(find.byType(ErrorRetryView), findsNothing);
    expect(find.text('مستوى النمو'), findsOneWidget);
    expect(find.text('هدفك المالي'), findsOneWidget);
  });
}
