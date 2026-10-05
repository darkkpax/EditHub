import 'package:edithub/models/models.dart';
import 'package:edithub/state/providers.dart';
import 'package:edithub/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'both tray clicks open a menu without showing or resizing the window',
    (tester) async {
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final name in ['window_manager', 'tray_manager']) {
        messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
          calls.add('$name/${call.method}');
          return null;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(MethodChannel(name), null),
        );
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectsProvider.overrideWith((_) => Stream.value(<ProjectInfo>[])),
            authProvider.overrideWith((_) async => null),
            icloudSyncingProvider.overrideWith((_) => Stream.value(false)),
          ],
          child: const MaterialApp(home: EditHubApp()),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, contains('tray_manager/setContextMenu'));
      calls.clear();
      for (final event in ['onTrayIconMouseDown', 'onTrayIconRightMouseDown']) {
        await messenger.handlePlatformMessage(
          'tray_manager',
          const StandardMethodCodec().encodeMethodCall(MethodCall(event)),
          (_) {},
        );
        await tester.pumpAndSettle();
      }
      expect(calls, [
        'tray_manager/popUpContextMenu',
        'tray_manager/popUpContextMenu',
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
