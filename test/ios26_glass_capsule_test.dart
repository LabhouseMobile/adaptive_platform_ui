import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
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

    test('widthFactor is omitted at 1 and sent when the slot is closing', () {
      expect(
        const GlassCapsuleItem(symbol: 'heart')
            .toNativeMap()
            .containsKey('widthFactor'),
        isFalse,
      );
      expect(
        const GlassCapsuleItem(
          symbol: 'heart',
          widthFactor: .5,
        ).toNativeMap()['widthFactor'],
        .5,
      );
    });

    test('id is sent when set and omitted when null', () {
      expect(
        const GlassCapsuleItem(symbol: 'heart').toNativeMap().containsKey('id'),
        isFalse,
      );
      expect(
        const GlassCapsuleItem(symbol: 'heart', id: 'like').toNativeMap()['id'],
        'like',
      );
    });

    test('fromAction forwards id and widthFactor', () {
      final action = AdaptiveAppBarAction(iosSymbol: 'heart', onPressed: () {});
      expect(GlassCapsuleItem.fromAction(action).id, isNull);
      expect(GlassCapsuleItem.fromAction(action, id: 'like').id, 'like');
      expect(
        GlassCapsuleItem.fromAction(action, id: 'like').toNativeMap()['id'],
        'like',
      );
      expect(
        GlassCapsuleItem.fromAction(action)
            .toNativeMap()
            .containsKey('widthFactor'),
        isFalse,
      );
      expect(
        GlassCapsuleItem.fromAction(
          action,
          widthFactor: .5,
        ).toNativeMap()['widthFactor'],
        .5,
      );
    });

    test('a prominent action reaches the native capsule as prominent', () {
      final plain = AdaptiveAppBarAction(iosSymbol: 'plus', onPressed: () {});
      final primary = AdaptiveAppBarAction(
        iosSymbol: 'checkmark',
        prominent: true,
        onPressed: () {},
      );

      expect(GlassCapsuleItem.fromAction(plain).prominent, isFalse);
      expect(
        GlassCapsuleItem.fromAction(plain)
            .toNativeMap()
            .containsKey('prominent'),
        isFalse,
      );
      expect(GlassCapsuleItem.fromAction(primary).prominent, isTrue);
      expect(
        GlassCapsuleItem.fromAction(primary).toNativeMap()['prominent'],
        isTrue,
      );
    });

    testWidgets('a prominent item with only a Flutter icon gets a white icon', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        Future<Color?> iconColor({required bool prominent, Color? tint}) async {
          await tester.pumpWidget(
            _host(
              SizedBox(
                width: IOS26GlassCapsule.width,
                height: IOS26GlassCapsule.height,
                child: IOS26GlassCapsule(
                  key: UniqueKey(),
                  items: [
                    GlassCapsuleItem(
                      prominent: prominent,
                      tint: tint,
                      fallback: const Icon(Icons.check),
                    ),
                  ],
                  onTap: (_) {},
                ),
              ),
            ),
          );
          return IconTheme.of(tester.element(find.byIcon(Icons.check))).color;
        }

        expect(
          await iconColor(prominent: true, tint: CupertinoColors.systemBlue),
          CupertinoColors.white,
        );
        expect(await iconColor(prominent: false), isNot(CupertinoColors.white));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('sends symbol size and weight only when they are set', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        Future<Map<dynamic, dynamic>> paramsOf({
          double? symbolSize,
          FontWeight? symbolWeight,
        }) async {
          await tester.pumpWidget(
            _host(
              SizedBox(
                width: IOS26GlassCapsule.width,
                height: IOS26GlassCapsule.height,
                child: IOS26GlassCapsule(
                  symbolSize: symbolSize,
                  symbolWeight: symbolWeight,
                  items: const [GlassCapsuleItem(symbol: 'heart')],
                  onTap: (_) {},
                ),
              ),
            ),
          );
          final view = tester.widget<UiKitView>(find.byType(UiKitView));
          return view.creationParams! as Map;
        }

        final plain = await paramsOf();
        expect(plain.containsKey('symbolSize'), isFalse);
        expect(plain.containsKey('symbolWeight'), isFalse);
        expect(plain.containsKey('axis'), isFalse);

        await tester.pumpWidget(
          _host(
            SizedBox(
              width: IOS26GlassCapsule.actionsWidth(1),
              height: IOS26GlassCapsule.height,
              child: IOS26GlassCapsule(
                axis: Axis.horizontal,
                items: const [GlassCapsuleItem(symbol: 'heart')],
                onTap: (_) {},
              ),
            ),
          ),
        );
        final horizontal =
            tester.widget<UiKitView>(find.byType(UiKitView)).creationParams!
                as Map;
        expect(horizontal['axis'], 'horizontal');

        final sized = await paramsOf(
          symbolSize: 19,
          symbolWeight: FontWeight.w600,
        );
        expect(sized['symbolSize'], 19);
        expect(sized['symbolWeight'], FontWeight.w600.value);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('actionsWidthFor keeps full slots and adds the closing ones', () {
      expect(
        IOS26GlassCapsule.actionsWidthFor([1, 1, 1]),
        IOS26GlassCapsule.actionsWidth(3),
      );
      expect(IOS26GlassCapsule.actionsWidthFor([0.5, 1]), 74);
      expect(IOS26GlassCapsule.actionsWidthFor([1, 0.5, 1]), 126);
      expect(IOS26GlassCapsule.actionsWidthFor([1.5, -1]), 48);
      expect(IOS26GlassCapsule.actionsWidthFor([0.5]), 26);
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
