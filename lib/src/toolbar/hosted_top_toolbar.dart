import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../style/sf_symbol.dart';
import '../widgets/adaptive_app_bar_action.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/ios26/ios26_native_toolbar.dart';
import 'duo_vertical_bar.dart';
import 'toolbar_blend.dart';
import 'toolbar_registry.dart';

/// Height of the toolbar's content area, excluding the status bar.
const double kHostedToolbarHeight = 44.0;

/// The actions the top toolbar shows: all of them if they fit in [max],
/// otherwise the first `max - 1` and an ellipsis whose native menu holds the
/// rest, in their order. The iPhone Duo vertical bar does the same with the
/// items that do not fit in it.
List<AdaptiveAppBarAction> fitTopToolbarActions(
  List<AdaptiveAppBarAction> actions, {
  int max = kMaxToolbarActions,
}) {
  assert(max >= 1, 'max must leave room for the overflow menu');
  if (actions.length <= max) return actions;
  return [
    ...actions.take(max - 1),
    AdaptiveAppBarAction(
      iosSymbol: 'ellipsis.circle',
      icon: CupertinoIcons.ellipsis,
      label: 'More',
      onPressed: () {},
      menu: actions.skip(max - 1).toList(),
    ),
  ];
}

/// What one page contributes to the top toolbar.
@immutable
class TopToolbarContent {
  const TopToolbarContent({
    this.title,
    this.titleOverlay,
    this.customLeading,
    this.impliesBack = false,
    this.actions = const <AdaptiveAppBarAction>[],
    this.tint,
    this.navigator,
  });

  /// No page owns the chrome, the page has no toolbar, or it draws a
  /// non-native bar of its own: nothing to show.
  ///
  /// With [titleOnly] the controls are left out, because the iPhone Duo
  /// vertical bar shows them instead.
  factory TopToolbarContent.of(ToolbarEntry? entry, {bool titleOnly = false}) {
    final appBar = entry?.appBar;
    if (entry == null || appBar == null || !appBar.useNativeToolbar) {
      return const TopToolbarContent();
    }
    return TopToolbarContent(
      title: appBar.title,
      titleOverlay: entry.titleOverlay,
      customLeading: titleOnly ? null : appBar.leading,
      impliesBack: !titleOnly && entry.impliesBackButton,
      actions: titleOnly
          ? const <AdaptiveAppBarAction>[]
          : appBar.actions ?? const <AdaptiveAppBarAction>[],
      tint: appBar.tintColor,
      navigator: entry.navigator,
    );
  }

  final String? title;

  /// A Flutter-drawn title (custom widget, or title with subtitle). The
  /// native title is left empty while one is shown.
  final Widget? titleOverlay;
  final Widget? customLeading;
  final bool impliesBack;
  final List<AdaptiveAppBarAction> actions;
  final Color? tint;
  final NavigatorState? navigator;

  bool get isEmpty =>
      title == null &&
      titleOverlay == null &&
      customLeading == null &&
      !impliesBack &&
      actions.isEmpty;
}

/// The one top toolbar of the app. It stays where it is while pages come and
/// go underneath it; only its items change.
///
/// It works exactly like the iPhone Duo vertical bar: every page involved in
/// a transition gets a layer of its own (here a native Liquid Glass
/// navigation bar), the layers are blended as [ToolbarBlend] dictates, so the
/// outgoing items fade out before the incoming ones fade in, in step with the
/// route transition and with a back swipe. A back button that both pages show
/// is one control in a layer of its own and stays put.
class HostedTopToolbar extends StatelessWidget {
  const HostedTopToolbar({
    super.key,
    required this.blend,
    this.titleOnly = false,
    this.topStrip,
    this.isFoldable = false,
    this.coveredOpacity = kToolbarCoveredOpacity,
  });

  final ToolbarBlend blend;

  /// True on iPhone Duo, where the controls live in the vertical bar.
  final bool titleOnly;

  /// On the iPhone Duo inner display in portrait, the hardware strip at the
  /// top: the bar is drawn inside it, level with the clock and ending before
  /// the status cluster, as the system draws its own. Null draws the bar
  /// below the top inset.
  final DuoTopStrip? topStrip;

  /// Whether the device folds (iPhone Duo). A phone has no window controls,
  /// so the back button never makes room for them there.
  final bool isFoldable;

  /// Opacity of the toolbar while a dialog or sheet covers the page that owns
  /// it.
  final double coveredOpacity;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: blend, builder: _build);
  }

  Widget _build(BuildContext context, Widget? _) {
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final upperEntry = blend.upper;
    final lowerEntry = blend.lower;
    final upper = TopToolbarContent.of(upperEntry, titleOnly: titleOnly);
    final lower = TopToolbarContent.of(lowerEntry, titleOnly: titleOnly);
    final upperOwns = blend.upperOwns;
    final upperOpacity = blend.upperOpacity;
    final lowerOpacity = blend.lowerOpacity;

    final upperBack = upper.impliesBack && upper.customLeading == null;
    final lowerBack = lower.impliesBack && lower.customLeading == null;
    final Animation<double>? backOpacity = switch ((upperBack, lowerBack)) {
      (true, true) => kAlwaysCompleteAnimation,
      (true, false) => upperOpacity,
      (false, true) => lowerOpacity,
      (false, false) => null,
    };

    // The bar's backdrop belongs to the chrome, not to a page: it only fades
    // when the toolbar as a whole comes or goes.
    final Animation<double> backdropOpacity = switch ((
      upper.isEmpty,
      lower.isEmpty,
    )) {
      (false, false) => kAlwaysCompleteAnimation,
      (false, true) =>
        blend.isBlending && lowerEntry != null
            ? upperOpacity
            : kAlwaysCompleteAnimation,
      (true, false) => lowerOpacity,
      (true, true) => kAlwaysDismissedAnimation,
    };

    // How far down the chrome reaches, and the slot the bar's 44 points of
    // content take in it: the bottom of the reach below the top inset, or
    // the strip's bar row beside the status cluster.
    final strip = titleOnly ? null : topStrip;
    final double height;
    var slotTop = 0.0;
    var slotRight = 0.0;
    double? slotHeight;
    if (titleOnly) {
      height = kDuoTitleBandHeight;
    } else if (strip != null) {
      height = strip.height;
      slotTop = strip.barTop;
      slotRight = strip.trailingClearance;
      slotHeight = kHostedToolbarHeight;
    } else {
      height = kHostedToolbarHeight + topInset;
    }

    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: height,
        child: IgnorePointer(
          ignoring: blend.ownerIsCovered,
          child: FadeTransition(
            opacity: blend.chromeOpacityFor(coveredOpacity),
            // Every layer is keyed, so a page's native bar survives the start
            // and the end of a blend instead of being torn down and rebuilt.
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                FadeTransition(
                  key: const ValueKey<String>('adaptive_toolbar_backdrop'),
                  opacity: backdropOpacity,
                  child: titleOnly
                      ? const DuoTitleBackdrop()
                      : _Backdrop(height: height),
                ),
                // The same widgets in every pose, so a rotation moves the
                // native bars instead of rebuilding them.
                Positioned(
                  key: const ValueKey<String>('adaptive_toolbar_slot'),
                  top: slotTop,
                  left: 0,
                  right: slotRight,
                  height: slotHeight ?? height,
                  // In the strip the bar is already clear of the top inset.
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: strip != null,
                    child: Stack(
                      fit: StackFit.expand,
                      clipBehavior: Clip.none,
                      children: [
                        if (lowerEntry != null && !lower.isEmpty)
                          _layer(
                            key: ValueKey<Object>(lowerEntry.id),
                            content: lower,
                            opacity: lowerOpacity,
                            interactive: !upperOwns,
                            inStrip: strip != null,
                          ),
                        if (upperEntry != null && !upper.isEmpty)
                          _layer(
                            key: ValueKey<Object>(upperEntry.id),
                            content: upper,
                            opacity: upperOpacity,
                            interactive: upperOwns,
                            inStrip: strip != null,
                          ),
                        if (backOpacity != null)
                          Positioned(
                            key: const ValueKey<String>(
                              'adaptive_toolbar_back',
                            ),
                            left:
                                16 +
                                (!isFoldable && _isWindowed(context) ? 62 : 0),
                            bottom: 3,
                            child: FadeTransition(
                              key: const ValueKey<String>(
                                'adaptive_toolbar_back_fade',
                              ),
                              opacity: backOpacity,
                              child: _BackButton(
                                navigator:
                                    (upperOwns ? upper : lower).navigator,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One page's bar. The back button is not part of it: the shared one is
  /// drawn on top of all page layers.
  Widget _layer({
    required Key key,
    required TopToolbarContent content,
    required Animation<double> opacity,
    required bool interactive,
    required bool inStrip,
  }) {
    final actions = fitTopToolbarActions(content.actions);
    return FadeTransition(
      key: key,
      opacity: opacity,
      child: IgnorePointer(
        ignoring: !interactive,
        child: titleOnly
            // On iPhone Duo the title sits at the leading edge and the
            // controls are in the trailing bar, so there is no bar to draw.
            ? DuoToolbarTitle(
                title: content.title,
                titleWidget: content.titleOverlay,
              )
            : defaultTargetPlatform == TargetPlatform.iOS
            ? IOS26NativeToolbar(
                // The safe area is read once, when the native view is made.
                key: ValueKey<bool>(inStrip),
                ignoresSafeArea: inStrip,
                title: content.title,
                titleWidget: content.titleOverlay,
                leading: content.customLeading,
                actions: actions,
                tintColor: content.tint,
                showsGradient: false,
                onActionTap: (index) {
                  if (index >= 0 && index < actions.length) {
                    actions[index].onPressed();
                  }
                },
                onMenuActionTap: (index, entry) {
                  if (index < 0 || index >= actions.length) return;
                  final menu = actions[index].menu;
                  if (menu != null && entry >= 0 && entry < menu.length) {
                    menu[entry].onPressed();
                  }
                },
              )
            : _FallbackBar(content: content, actions: actions),
      ),
    );
  }

  /// Whether the app runs in a window smaller than the display (iPadOS),
  /// where the system's window controls take the bar's leading corner.
  ///
  /// Only meaningful off iPhone Duo: there the display and the app's view
  /// differ in size although there is no window to control, so the caller
  /// skips it on a foldable.
  static bool _isWindowed(BuildContext context) {
    final display = View.of(context).display.size;
    final viewport =
        MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);
    return (display.longestSide - viewport.longestSide).abs() > 1 ||
        (display.shortestSide - viewport.shortestSide).abs() > 1;
  }
}

/// The soft gradient that keeps the bar readable over scrolling content.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.height});

  /// How far down the toolbar reaches; the gradient runs on below it.
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final base = dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    return IgnorePointer(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        maxHeight: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) => Container(
            // Runs on below the bar for a smooth fade into the content.
            height: height + 30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.4, 0.7, 1.0],
                colors: [
                  base.withValues(alpha: 0.85),
                  base.withValues(alpha: 0.6),
                  base.withValues(alpha: 0.2),
                  base.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Back for the page that owns the chrome, performed on that page's own
/// navigator so nested navigators (tabs, shell routes) pop the right stack.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.navigator});

  final NavigatorState? navigator;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      width: 38,
      child: AdaptiveButton.sfSymbol(
        onPressed: () => navigator?.maybePop(),
        sfSymbol: const SFSymbol('chevron.left', size: 20),
      ),
    );
  }
}

/// Stand-in for the native bar where there is no UIKit (widget tests).
class _FallbackBar extends StatelessWidget {
  const _FallbackBar({required this.content, required this.actions});

  final TopToolbarContent content;

  /// [content]'s actions as the bar shows them ([fitTopToolbarActions]).
  final List<AdaptiveAppBarAction> actions;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: kHostedToolbarHeight,
        child: Row(
          children: [
            if (content.customLeading != null) content.customLeading!,
            Expanded(
              child: Center(
                child:
                    content.titleOverlay ??
                    (content.title != null ? Text(content.title!) : null),
              ),
            ),
            for (final action in actions)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: action.onPressed,
                child: action.icon != null
                    ? Icon(action.icon)
                    : Text(action.title ?? ''),
              ),
          ],
        ),
      ),
    );
  }
}
