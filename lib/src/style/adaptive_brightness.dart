import 'package:flutter/widgets.dart';

/// The brightness this package's widgets are drawn in: the native iOS 26
/// views (menus, toolbars, tab bars, glass capsules, buttons, alerts, ...) and
/// the Cupertino fallbacks (cards, tiles, snack bars, tooltips, the scaffold's
/// default text colour).
///
/// By default that is the device's brightness, which is wrong for an app that
/// picks its own: a light-mode app on a dark-mode device would get dark native
/// components over a light screen. Place an [AdaptiveBrightness] above them
/// and they follow it instead.
///
/// * Put it above the app's navigator, in `MaterialApp.builder` or
///   `CupertinoApp.builder`, and wrap [AdaptiveToolbarHost] with it, or give the
///   host a `brightness`: the host builds the top toolbar and the Duo bar
///   above its child. Only an app-level scope reaches dialogs, snack bars,
///   tooltips and menus, which are pushed on the root navigator or inserted in
///   its overlay.
/// * Read the app's own brightness: `Theme.of(context).brightness` in a
///   `MaterialApp`, `CupertinoTheme.brightnessOf(context)` in a `CupertinoApp`.
/// * [AdaptiveApp] already does this from its `themeMode`; do not add the
///   scope to its `builder`, which sits above the theme and would force light.
///
/// [AdaptiveToolbarHost], [AdaptiveScaffold] and [AdaptiveButton] also take a
/// `brightness` that installs this scope for their subtree, and
/// [IOS26GlassCapsule] a `brightness` for its own drawing. Under a host the
/// top toolbar and the Duo bar are the host's, so an [AdaptiveScaffold]'s
/// `brightness` covers its body only. Without any of them, everything follows
/// the device, as before.
class AdaptiveBrightness extends InheritedWidget {
  const AdaptiveBrightness({
    super.key,
    required this.brightness,
    required super.child,
  });

  /// The brightness native components below are drawn in, or null to set
  /// nothing: [maybeOf] is then null below, and [of] the device's. The widgets
  /// that take a `brightness` install a scope with a null value when they are
  /// given none, so their tree keeps its shape whether it is set or not.
  final Brightness? brightness;

  /// The brightness set by the nearest [AdaptiveBrightness], or null when
  /// there is none.
  static Brightness? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AdaptiveBrightness>()
      ?.brightness;

  /// The brightness native components draw in: the nearest
  /// [AdaptiveBrightness], else the device's.
  static Brightness of(BuildContext context) =>
      maybeOf(context) ?? MediaQuery.platformBrightnessOf(context);

  @override
  bool updateShouldNotify(AdaptiveBrightness oldWidget) =>
      brightness != oldWidget.brightness;
}
