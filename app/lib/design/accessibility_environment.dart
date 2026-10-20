import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the phone's accessibility settings say that Flutter does not report itself. Reduce Transparency is
/// on the iOS side only; Increase Contrast and Reduce Motion come through `MediaQuery`.
abstract class AccessibilityEnvironment {
  Future<bool> reduceTransparency();

  /// Calls [onChange] whenever the setting changes while the app runs.
  void listen(void Function(bool reduceTransparency) onChange);
}

class ChannelAccessibilityEnvironment implements AccessibilityEnvironment {
  static const channel = MethodChannel('ucsc_router/accessibility');

  @override
  Future<bool> reduceTransparency() async {
    try {
      return await channel.invokeMethod<bool>('reduceTransparency') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  void listen(void Function(bool reduceTransparency) onChange) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'reduceTransparencyChanged' && call.arguments is bool) onChange(call.arguments as bool);
    });
  }
}

final accessibilityEnvironmentProvider = Provider<AccessibilityEnvironment>((ref) => ChannelAccessibilityEnvironment());

class ReduceTransparency extends Notifier<bool> {
  @override
  bool build() {
    final environment = ref.read(accessibilityEnvironmentProvider);
    environment.reduceTransparency().then((on) {
      if (ref.mounted) state = on;
    });
    environment.listen((on) {
      if (ref.mounted) state = on;
    });
    return false;
  }
}

final reduceTransparencyProvider = NotifierProvider<ReduceTransparency, bool>(ReduceTransparency.new);

/// Glass is drawn on iOS 26 and later. Anything else gets the solid look, as does a build made with
/// `--dart-define=FORCE_SOLID=true`, which is how the fallback is checked in the Simulator.
bool osSupportsGlass({TargetPlatform? platform, String? version}) {
  if ((platform ?? defaultTargetPlatform) != TargetPlatform.iOS) return false;
  final major = RegExp(r'\d+').firstMatch(version ?? Platform.operatingSystemVersion)?.group(0);
  return major != null && int.parse(major) >= 26;
}

final glassSupportedProvider = Provider<bool>((ref) => !const bool.fromEnvironment('FORCE_SOLID') && osSupportsGlass());

/// Whether glass surfaces are drawn as glass right now: the platform supports it and neither Reduce
/// Transparency nor Increase Contrast is on.
bool glassOn(BuildContext context, WidgetRef ref) =>
    ref.watch(glassSupportedProvider) && !ref.watch(reduceTransparencyProvider) && !MediaQuery.highContrastOf(context);
