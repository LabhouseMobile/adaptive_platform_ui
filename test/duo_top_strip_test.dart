import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/duo_vertical_bar.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_top_toolbar.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/ios26_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

/// The iPhone Duo inner display in portrait, as the iOS 27.1 simulator
/// reports it: the hardware strip is the top inset.
const Size duoPortrait = Size(669, 951);
const double duoStripHeight = 84;

const FoldableCapabilities foldable = FoldableCapabilities(
  supportLevel: FoldableSupportLevel.available,
  isFoldable: true,
  hingeApiPresent: true,
  regionApiPresent: true,
  angleUnitVerified: false,
  strategy: 'test',
);

FoldableData fold({
  bool isFoldable = true,
  List<ReservedRegion> regions = const [],
}) => FoldableData(
  capabilities: isFoldable ? foldable : FoldableCapabilities.unsupported,
  status: HingeStatus.unknown,
  angleDegrees: null,
  regions: regions,
  displayFeatures: const [],
);

ReservedRegion occlusion(Rect bounds, {bool isActive = true}) => ReservedRegion(
  kind: ReservedRegionKind.occlusion,
  bounds: bounds,
  isActive: isActive,
);

DuoTopStrip? resolve({
  EdgeInsets viewPadding = const EdgeInsets.only(
    top: duoStripHeight,
    bottom: 20,
  ),
  DuoPose? pose,
  FoldableData? data,
}) => DuoLayout.resolveTopStrip(
  viewPadding: viewPadding,
  size: duoPortrait,
  pose: pose,
  fold: data ?? fold(),
  barHeight: kHostedToolbarHeight,
);

void useWindow(WidgetTester tester, Size size, {required double top}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: top, bottom: 20);
  tester.view.viewPadding = FakeViewPadding(top: top, bottom: 20);
  addTearDown(tester.view.reset);
}

Widget hostedApp({
  required FoldableData data,
  required Widget home,
  GlobalKey<NavigatorState>? navigatorKey,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  builder: (context, child) =>
      AdaptiveToolbarHost(debugFold: data, child: child!),
  home: home,
);

/// A page that publishes its app bar to the host.
Widget page(String title) => AdaptiveScaffold(
  appBar: AdaptiveAppBar(
    title: title,
    useNativeToolbar: true,
    actions: [AdaptiveAppBarAction(icon: Icons.add, onPressed: () {})],
  ),
  body: Center(child: Text('body:$title')),
);

/// The iOS 26 scaffold itself, reporting the padding its body gets.
Widget scaffoldPage(
  String title, {
  required ValueChanged<EdgeInsets> onPadding,
}) => IOS26Scaffold(
  title: title,
  children: [
    Builder(
      builder: (context) {
        onPadding(MediaQuery.paddingOf(context));
        return Text('body:$title');
      },
    ),
  ],
);

Finder get bar => find.byType(HostedTopToolbar);
Finder get slot => find.byKey(const ValueKey<String>('adaptive_toolbar_slot'));
Finder get back => find.byKey(const ValueKey<String>('adaptive_toolbar_back'));

void main() {
  group('DuoLayout.resolveTopStrip', () {
    test('the Duo inner display in portrait has one', () {
      expect(
        resolve(),
        const DuoTopStrip(
          height: duoStripHeight,
          trailingClearance: kDuoStatusClusterClearance,
        ),
      );
    });

    test('other devices have none', () {
      // An ordinary iPhone in portrait: the same kind of top inset.
      expect(
        resolve(
          viewPadding: const EdgeInsets.only(top: 62, bottom: 34),
          data: fold(isFoldable: false),
        ),
        isNull,
      );
      expect(
        DuoLayout.resolveTopStrip(
          viewPadding: const EdgeInsets.only(top: duoStripHeight),
          size: duoPortrait,
          pose: null,
          fold: null,
          barHeight: kHostedToolbarHeight,
        ),
        isNull,
      );
    });

    test('a vertical bar pose has none', () {
      expect(
        resolve(
          pose: const DuoPose(
            side: DuoBarSide.right,
            stripWidth: 84,
            reservedBySystem: true,
          ),
        ),
        isNull,
      );
    });

    test('an inset too short to hold the bar is not a strip', () {
      expect(
        resolve(
          viewPadding: const EdgeInsets.only(
            top: kDuoTopBarTop + kHostedToolbarHeight - 1,
          ),
        ),
        isNull,
      );
    });

    test('a status cluster reported further in widens the clearance', () {
      final strip = resolve(
        data: fold(regions: [occlusion(const Rect.fromLTRB(529, 0, 669, 70))]),
      );
      expect(strip!.trailingClearance, 140);
    });

    test('regions that are not the status cluster keep the measured room', () {
      final strip = resolve(
        data: fold(
          regions: [
            // The camera alone, inside the measured room.
            occlusion(const Rect.fromLTRB(590, 0, 669, 60)),
            // Inactive, below the strip, or in the leading half.
            occlusion(const Rect.fromLTRB(400, 0, 669, 70), isActive: false),
            occlusion(const Rect.fromLTRB(400, 100, 669, 160)),
            occlusion(const Rect.fromLTRB(100, 0, 200, 70)),
            const ReservedRegion(
              kind: ReservedRegionKind.division,
              bounds: Rect.fromLTRB(0, 455, 669, 495),
              isActive: true,
            ),
          ],
        ),
      );
      expect(strip!.trailingClearance, kDuoStatusClusterClearance);
    });
  });

  group('the top toolbar on the Duo inner display in portrait', () {
    testWidgets('sits in the strip, level with the clock, before the cluster', (
      tester,
    ) async {
      useWindow(tester, duoPortrait, top: duoStripHeight);
      await tester.pumpWidget(hostedApp(data: fold(), home: page('Home')));
      await tester.pump();

      final reach = tester.getRect(
        find.descendant(of: bar, matching: find.byType(SizedBox)).first,
      );
      expect(reach.top, 0);
      expect(reach.height, duoStripHeight);
      expect(
        tester.getRect(slot),
        Rect.fromLTRB(
          0,
          kDuoTopBarTop,
          duoPortrait.width - kDuoStatusClusterClearance,
          kDuoTopBarTop + kHostedToolbarHeight,
        ),
      );
      // The bar is placed inside the inset, so it does not inset itself.
      final barContext = tester.element(
        find.descendant(of: slot, matching: find.text('Home')),
      );
      expect(MediaQuery.paddingOf(barContext).top, 0);
    });

    testWidgets('takes no room below the strip from the page body', (
      tester,
    ) async {
      useWindow(tester, duoPortrait, top: duoStripHeight);
      EdgeInsets? padding;
      await tester.pumpWidget(
        hostedApp(
          data: fold(),
          home: scaffoldPage('Home', onPadding: (p) => padding = p),
        ),
      );
      await tester.pump();

      expect(padding!.top, duoStripHeight);
    });
  });

  group('other devices keep the bar below the top inset', () {
    testWidgets('an iPhone in portrait', (tester) async {
      useWindow(tester, const Size(402, 874), top: 62);
      EdgeInsets? padding;
      await tester.pumpWidget(
        hostedApp(
          data: fold(isFoldable: false),
          home: scaffoldPage('Home', onPadding: (p) => padding = p),
        ),
      );
      await tester.pump();

      expect(
        tester.getRect(slot),
        const Rect.fromLTWH(0, 0, 402, 62 + kHostedToolbarHeight),
      );
      expect(padding!.top, 62 + kHostedToolbarHeight);
    });
  });
}
