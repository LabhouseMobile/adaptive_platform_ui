import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// [child] on a device in [device] brightness.
Widget _onDevice(Brightness device, Widget child) => MediaQuery(
  data: MediaQueryData(platformBrightness: device),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

class _Probe extends StatelessWidget {
  const _Probe(this.onBuild);

  final ValueChanged<Brightness> onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild(AdaptiveBrightness.of(context));
    return const SizedBox.shrink();
  }
}

/// Counts how many times its State was created.
class _CountInit extends StatefulWidget {
  const _CountInit(this.onInit);

  final VoidCallback onInit;

  @override
  State<_CountInit> createState() => _CountInitState();
}

class _CountInitState extends State<_CountInit> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  group('AdaptiveBrightness', () {
    testWidgets('follows the device without a scope', (tester) async {
      Brightness? seen;
      await tester.pumpWidget(
        _onDevice(Brightness.dark, _Probe((b) => seen = b)),
      );

      expect(seen, Brightness.dark);
    });

    testWidgets('a scope wins over the device and updates dependents', (
      tester,
    ) async {
      Brightness? seen;
      Widget app(Brightness scope) => _onDevice(
        Brightness.dark,
        AdaptiveBrightness(brightness: scope, child: _Probe((b) => seen = b)),
      );

      await tester.pumpWidget(app(Brightness.light));
      expect(seen, Brightness.light);

      await tester.pumpWidget(app(Brightness.dark));
      expect(seen, Brightness.dark);
    });

    testWidgets('going between null and a brightness keeps the state below', (
      tester,
    ) async {
      var inits = 0;
      final widgets = <String, Widget Function(Brightness?, Widget)>{
        'AdaptiveButton': (b, child) =>
            AdaptiveButton.child(brightness: b, onPressed: () {}, child: child),
        'AdaptiveScaffold': (b, child) =>
            AdaptiveScaffold(brightness: b, body: child),
        'AdaptiveToolbarHost': (b, child) =>
            AdaptiveToolbarHost(brightness: b, child: child),
      };
      for (final entry in widgets.entries) {
        inits = 0;
        Widget app(Brightness? b) => _onDevice(
          Brightness.dark,
          Material(child: entry.value(b, _CountInit(() => inits++))),
        );

        await tester.pumpWidget(app(null));
        await tester.pumpWidget(app(Brightness.light));
        await tester.pumpWidget(app(null));

        expect(inits, 1, reason: '${entry.key} remounted its subtree');
      }
    });

    testWidgets('AdaptiveButton, AdaptiveScaffold and the host set the scope', (
      tester,
    ) async {
      Brightness? seen;
      Future<Brightness?> seenIn(Widget Function(Widget probe) wrap) async {
        seen = null;
        await tester.pumpWidget(
          _onDevice(
            Brightness.dark,
            Material(child: wrap(_Probe((b) => seen = b))),
          ),
        );
        return seen;
      }

      expect(
        await seenIn(
          (probe) => AdaptiveButton.child(
            brightness: Brightness.light,
            onPressed: () {},
            child: probe,
          ),
        ),
        Brightness.light,
      );
      expect(
        await seenIn(
          (probe) =>
              AdaptiveScaffold(brightness: Brightness.light, body: probe),
        ),
        Brightness.light,
      );
      expect(
        await seenIn(
          (probe) =>
              AdaptiveToolbarHost(brightness: Brightness.light, child: probe),
        ),
        Brightness.light,
      );
    });
  });

  group('native components', () {
    Future<Map<dynamic, dynamic>> capsuleParams(
      WidgetTester tester, {
      Brightness? brightness,
      Brightness? scope,
    }) async {
      Widget capsule = SizedBox(
        width: IOS26GlassCapsule.width,
        height: IOS26GlassCapsule.height,
        child: IOS26GlassCapsule(
          key: UniqueKey(),
          brightness: brightness,
          items: const [GlassCapsuleItem(symbol: 'heart')],
          onTap: (_) {},
        ),
      );
      if (scope != null) {
        capsule = AdaptiveBrightness(brightness: scope, child: capsule);
      }
      await tester.pumpWidget(_onDevice(Brightness.dark, capsule));
      return tester.widget<UiKitView>(find.byType(UiKitView)).creationParams!
          as Map;
    }

    testWidgets('the glass capsule draws in the app brightness', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        expect((await capsuleParams(tester))['isDark'], isTrue);
        expect(
          (await capsuleParams(tester, scope: Brightness.light))['isDark'],
          isFalse,
        );
        expect(
          (await capsuleParams(tester, brightness: Brightness.light))['isDark'],
          isFalse,
        );
        expect(
          (await capsuleParams(
            tester,
            brightness: Brightness.light,
            scope: Brightness.dark,
          ))['isDark'],
          isFalse,
          reason: 'the widget parameter wins over the scope',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a native button is sent the scope and its changes', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final calls = <MethodCall>[];
      MethodChannel? channel;
      try {
        Widget button(Brightness scope) => _onDevice(
          Brightness.dark,
          AdaptiveBrightness(
            brightness: scope,
            child: IOS26Button.sfSymbol(
              onPressed: () {},
              sfSymbol: const SFSymbol('heart'),
            ),
          ),
        );

        await tester.pumpWidget(button(Brightness.light));
        final params =
            tester.widget<UiKitView>(find.byType(UiKitView)).creationParams!
                as Map;
        expect(params['isDark'], isFalse);

        channel = MethodChannel(
          'adaptive_platform_ui/ios26_button_${params['id']}',
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call);
            return null;
          },
        );

        await tester.pumpWidget(button(Brightness.dark));
        final sent = calls.where((call) => call.method == 'setBrightness');
        expect(sent, hasLength(1));
        expect((sent.single.arguments as Map)['isDark'], isTrue);
      } finally {
        if (channel != null) {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
        }
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('the capsule draws its Flutter icon in its own brightness', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        Future<int?> iconColor(Brightness? brightness) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData.dark(),
              home: Center(
                child: SizedBox(
                  width: IOS26GlassCapsule.width,
                  height: IOS26GlassCapsule.height,
                  child: IOS26GlassCapsule(
                    key: UniqueKey(),
                    brightness: brightness,
                    items: const [GlassCapsuleItem(fallback: Icon(Icons.add))],
                    onTap: (_) {},
                  ),
                ),
              ),
            ),
          );
          return IconTheme.of(
            tester.element(find.byIcon(Icons.add)),
          ).color?.toARGB32();
        }

        expect(
          await iconColor(Brightness.dark),
          CupertinoColors.label.darkColor.toARGB32(),
        );
        expect(
          await iconColor(Brightness.light),
          CupertinoColors.label.color.toARGB32(),
          reason: 'a light capsule in a dark app is not a white icon on glass',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('IOS26SegmentedControl', () {
    // The channel name carries a static counter, so listen on a range.
    Future<List<bool>> sentIsDark(
      WidgetTester tester, {
      required Brightness cupertino,
      Brightness? scope,
    }) async {
      final sent = <bool>[];
      final channels = [
        for (var id = 0; id < 100; id++)
          MethodChannel('adaptive_platform_ui/ios26_segmented_control_$id'),
      ];
      for (final channel in channels) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'setBrightness') {
              sent.add((call.arguments as Map)['isDark'] as bool);
            }
            return null;
          },
        );
      }
      addTearDown(() {
        for (final channel in channels) {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
        }
      });

      Widget control = IOS26SegmentedControl(
        labels: const ['a', 'b'],
        selectedIndex: 0,
        onValueChanged: (_) {},
      );
      if (scope != null) {
        control = AdaptiveBrightness(brightness: scope, child: control);
      }
      await tester.pumpWidget(
        _onDevice(
          Brightness.dark,
          CupertinoTheme(
            data: CupertinoThemeData(brightness: cupertino),
            child: Material(child: control),
          ),
        ),
      );
      return sent;
    }

    testWidgets('a scope wins over the Cupertino theme', (tester) async {
      expect(
        await sentIsDark(
          tester,
          cupertino: Brightness.dark,
          scope: Brightness.light,
        ),
        [false],
      );
    });

    testWidgets('without a scope it follows the theme, not the device', (
      tester,
    ) async {
      expect(await sentIsDark(tester, cupertino: Brightness.light), [false]);
    });
  });
}
