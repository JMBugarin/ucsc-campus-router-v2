import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'glass.dart';
import 'tokens.dart';
import 'type.dart';

/// A pill button on glass. [prominent] is the accent-tinted one; a solid prominent button
/// (`FilledButton`) is what goes inside a glass card, where glass is not stacked.
class GlassButton extends ConsumerWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.prominent = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool prominent;
  final bool expand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final color = prominent ? c.accentOnFill : c.accentText;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, color: color), const SizedBox(width: Space.xs)],
        Flexible(child: Text(label, textAlign: TextAlign.center, style: AppText.headline.copyWith(color: color))),
      ],
    );
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      child: GlassSurface(
        level: GlassLevel.small,
        prominent: prominent,
        radius: Radii.pill,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.pill),
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 50),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
                child: Center(widthFactor: expand ? null : 1, child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A round glass button with an icon, such as locate me or the buttons beside a large title.
class GlassIconButton extends ConsumerWidget {
  const GlassIconButton({super.key, required this.icon, required this.tooltip, required this.onPressed, this.size = 50});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: tooltip,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: size,
          child: GlassSurface(
            level: GlassLevel.small,
            radius: size / 2,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPressed,
                child: Center(child: Icon(icon, color: c.accentText)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The search field on glass: a magnifier, the text, and a clear button once there is text.
class GlassSearchField extends ConsumerWidget {
  const GlassSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.hintText = 'Search a room or building',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final String hintText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return GlassSurface(
      level: GlassLevel.small,
      radius: Radii.pill,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => Row(
            children: [
              const SizedBox(width: Space.md),
              Icon(Icons.search, color: c.labelSecondary),
              const SizedBox(width: Space.xs),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  textInputAction: TextInputAction.search,
                  style: AppText.body.copyWith(color: c.labelPrimary),
                  cursorColor: c.accentText,
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: AppText.body.copyWith(color: c.labelSecondary),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: Space.sm),
                  ),
                ),
              ),
              if (value.text.isNotEmpty)
                IconButton(tooltip: 'Clear search', icon: Icon(Icons.cancel, color: c.labelSecondary), onPressed: onClear)
              else
                const SizedBox(width: Space.md),
            ],
          ),
        ),
      ),
    );
  }
}

class ModeOption<T> {
  const ModeOption({required this.value, required this.label, required this.icon});

  final T value;
  final String label;
  final IconData icon;
}

/// A segmented control on glass. The selected segment is the accent; each segment is at least 44 pt.
class ModeSelector<T> extends ConsumerWidget {
  const ModeSelector({super.key, required this.options, required this.selected, required this.onSelected});

  final List<ModeOption<T>> options;
  final T? selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return GlassSurface(
      level: GlassLevel.small,
      radius: Radii.pill,
      padding: const EdgeInsets.all(Space.xxs),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: o.value == selected,
                label: o.label,
                excludeSemantics: true,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    onTap: () => onSelected(o.value),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: o.value == selected ? c.accentFill : null,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xs),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: Space.xxs,
                            children: [
                              Icon(o.icon, color: o.value == selected ? c.accentOnFill : c.labelPrimary),
                              Text(
                                o.label,
                                style: AppText.subhead.copyWith(color: o.value == selected ? c.accentOnFill : c.labelPrimary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The floating tab bar: a glass capsule around a `NavigationBar`, so tabs keep their native semantics.
class GlassTabBar extends ConsumerWidget {
  const GlassTabBar({super.key, required this.selectedIndex, required this.onSelected, required this.destinations});

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<NavigationDestination> destinations;

  /// The height the bar takes at the default text size, margins included, for screens that scroll beneath it.
  static const double height = 66;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassSurface(
      radius: Radii.pill,
      padding: const EdgeInsets.all(Space.xxs),
      // The bar floats above the home indicator, so NavigationBar must not add that inset a second time.
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: NavigationBar(
          height: 58,
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          destinations: destinations,
        ),
      ),
    );
  }
}
