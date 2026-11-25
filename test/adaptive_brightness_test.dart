import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
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

    testWidgets('scoped is a no-op without a brightness', (tester) async {
      Brightness? seen;
      await tester.pumpWidget(
        _onDevice(
          Brightness.dark,
          AdaptiveBrightness.scoped(
            brightness: null,
            child: _Probe((b) => seen = b),
          ),
        ),
      );

      expect(seen, Brightness.dark);
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
  });
}
