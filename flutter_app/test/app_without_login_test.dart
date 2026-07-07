import 'package:edithub/models/models.dart';
import 'package:edithub/state/providers.dart';
import 'package:edithub/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tray menu stays compact', () {
    expect(kTrayMenuSize, const Size(176, 72));
  });

  testWidgets('opens the project shell without requiring a login', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider.overrideWith((_) async => <ProjectInfo>[]),
        ],
        child: const MaterialApp(home: EditHubApp()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('projects-sidebar')), findsOneWidget);
    expect(find.text('Войти в EditHub'), findsNothing);
  });
}
