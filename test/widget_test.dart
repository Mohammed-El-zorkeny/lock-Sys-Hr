import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:locksys_hr/app/app.dart';
import 'package:locksys_hr/features/auth/presentation/login_screen.dart';

void main() {
  testWidgets('App boots without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const LockSysHrApp());
    await tester.pump();

    expect(find.byType(LockSysHrApp), findsOneWidget);
  });

  testWidgets('Login screen renders on a small phone without overflow',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pump();

    expect(find.text('تسجيل الدخول'), findsWidgets);
    expect(find.text('اسم المستخدم'), findsWidgets);
    expect(find.text('رقم الهاتف'), findsWidgets);
    expect(find.text('هل نسيت كلمة السر؟'), findsOneWidget);
    expect(find.text('تواصل معنا'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
