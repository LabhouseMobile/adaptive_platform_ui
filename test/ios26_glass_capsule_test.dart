import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(home: Center(child: child));

void main() {
  group('IOS26GlassCapsule size helpers', () {
    test('vertical helpers are unchanged', () {
      expect(IOS26GlassCapsule.width, 48);
      expect(IOS26GlassCapsule.actionsHeight(1), 48);
      expect(IOS26GlassCapsule.actionsHeight(3), 152);
      expect(IOS26GlassCapsule.tabsHeight(4), 212);
    });

    test('horizontal width grows with the item count', () {
      expect(IOS26GlassCapsule.height, 48);
      expect(IOS26GlassCapsule.actionsWidth(1), 48);
      expect(IOS26GlassCapsule.actionsWidth(2), 100);
      expect(IOS26GlassCapsule.actionsWidth(3), 152);
    });

    test('horizontal width mirrors the vertical height', () {
      for (var n = 1; n <= 5; n++) {
        expect(
          IOS26GlassCapsule.actionsWidth(n),
          IOS26GlassCapsule.actionsHeight(n),
        );
      }
    });
  });

  group('IOS26GlassCapsule fallback layout', () {
    List<GlassCapsuleItem> items() => const [
      GlassCapsuleItem(
        symbol: 'a',
        fallback: SizedBox(key: Key('a'), width: 10, height: 10),
      ),
      GlassCapsuleItem(
        symbol: 'b',
        fallback: SizedBox(key: Key('b'), width: 10, height: 10),
      ),
      GlassCapsuleItem(
        symbol: 'c',
        fallback: SizedBox(key: Key('c'), width: 10, height: 10),
      ),
    ];

    testWidgets('defaults to vertical', (tester) async {
      expect(
        IOS26GlassCapsule(items: items(), onTap: (_) {}).axis,
        Axis.vertical,
      );
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: IOS26GlassCapsule.width,
            height: IOS26GlassCapsule.actionsHeight(3),
            child: IOS26GlassCapsule(items: items(), onTap: (_) {}),
          ),
        ),
      );
      final a = tester.getCenter(find.byKey(const Key('a')));
      final c = tester.getCenter(find.byKey(const Key('c')));
      expect(a.dx, c.dx);
      expect(c.dy, greaterThan(a.dy));
      expect(find.byType(Column), findsWidgets);
    });

    testWidgets('horizontal lays items out in a row and routes taps', (
      tester,
    ) async {
      final taps = <int>[];
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: IOS26GlassCapsule.actionsWidth(3),
            height: IOS26GlassCapsule.height,
            child: IOS26GlassCapsule(
              axis: Axis.horizontal,
              items: items(),
              onTap: taps.add,
            ),
          ),
        ),
      );
      final a = tester.getCenter(find.byKey(const Key('a')));
      final b = tester.getCenter(find.byKey(const Key('b')));
      final c = tester.getCenter(find.byKey(const Key('c')));
      expect(a.dy, c.dy);
      expect(b.dx - a.dx, closeTo(IOS26GlassCapsule.actionsWidth(3) / 3, 0.01));
      expect(c.dx, greaterThan(b.dx));

      await tester.tap(find.byKey(const Key('b')), warnIfMissed: false);
      expect(taps, [1]);
    });
  });
}
