import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthouse/app/smart_house_app.dart';
import 'package:smarthouse/features/electricity/data/mock_linky_repository.dart';

void main() {
  testWidgets('today dashboard renders key Linky metrics', (tester) async {
    await tester.pumpWidget(
      const SmartHouseApp(repository: MockLinkyRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('SmartHouse'), findsOneWidget);
    expect(find.text('Électricité'), findsOneWidget);

    await tester.tap(find.text('Électricité'));
    await tester.pumpAndSettle();

    expect(find.text("Aujourd'hui"), findsWidgets);
    expect(find.text('Heures pleines'), findsOneWidget);
    expect(find.text('Heures creuses'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);

    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();

    expect(find.text('Consommation passée'), findsOneWidget);
    expect(find.text('Jour'), findsWidgets);
    expect(find.text('Répartition horaire'), findsOneWidget);
  });
}
