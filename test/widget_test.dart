import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/main.dart';

void main() {
  testWidgets('renderiza interface principal do app', (WidgetTester tester) async {
    await tester.pumpWidget(const PersonalAgentApp());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(MaterialApp), findsOneWidget);

    final hasLoading = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    final hasLogin = find.text('Entrar').evaluate().isNotEmpty;
    final hasDashboard = find.byType(TabBar).evaluate().isNotEmpty;

    expect(hasLoading || hasLogin || hasDashboard, isTrue);
  });
}
