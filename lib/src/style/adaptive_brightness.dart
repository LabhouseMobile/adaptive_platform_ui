import 'package:flutter/widgets.dart';

/// The brightness the app is drawn in, for the native components.
///
/// Native iOS 26 components (menus, toolbars, tab bars, glass capsules,
/// buttons, ...) are told whether to draw light or dark. By default that is
/// the device's brightness, which is wrong for an app that picks its own: a
/// light-mode app on a dark-mode device would get dark native components over
/// a light screen. Place an [AdaptiveBrightness] above them (an app `builder`
/// is the right place) and they follow it instead.
///
/// [AdaptiveToolbarHost], [AdaptiveScaffold], [AdaptiveButton] and
/// [IOS26GlassCapsule] also take a `brightness` that installs this scope for
/// their subtree. Without any of them, everything follows the device, as
/// before.
class AdaptiveBrightness extends InheritedWidget {
  const AdaptiveBrightness({
    super.key,
    required this.brightness,
    required super.child,
  });

  /// The brightness native components below are drawn in.
  final Brightness brightness;

  /// Wraps [child] in an [AdaptiveBrightness] when [brightness] is set, and
  /// returns it untouched (keeping the inherited or device brightness)
  /// otherwise.
  static Widget scoped({
    required Brightness? brightness,
    required Widget child,
  }) {
    if (brightness == null) return child;
    return AdaptiveBrightness(brightness: brightness, child: child);
  }

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
