import 'package:edithub/ui/design/glass_surface.dart';
import 'package:edithub/ui/design/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('GlassSurface uses a live BackdropFilter', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: GlassSurface(child: Text('glass'))),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('PressableScale compresses while pressed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PressableScale(onTap: () {}, child: const Text('press')),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('press')),
    );
    await tester.pump();

    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      lessThan(1),
    );
    await gesture.up();
  });
}
