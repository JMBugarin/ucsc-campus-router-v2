import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
        if (icon != null) ...[
          Icon(icon, color: color),
          const SizedBox(width: Space.xs),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppText.headline.copyWith(color: color),
          ),
        ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.lg,
                  vertical: Space.sm,
                ),
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
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 50,
  });

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
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: Space.sm,
                    ),
                  ),
                ),
              ),
              if (value.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear search',
                  icon: Icon(Icons.cancel, color: c.labelSecondary),
                  onPressed: onClear,
                )
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
  const ModeOption({
    required this.value,
    required this.label,
    required this.icon,
  });

  final T value;
  final String label;
  final IconData icon;
}

/// A segmented control on glass. The selected segment is the accent; each segment is at least 44 pt.
class ModeSelector<T> extends ConsumerWidget {
  const ModeSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

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
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.xs,
                            vertical: Space.xs,
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: Space.xxs,
                            children: [
                              Icon(
                                o.icon,
                                color: o.value == selected
                                    ? c.accentOnFill
                                    : c.labelPrimary,
                              ),
                              Text(
                                o.label,
                                style: AppText.subhead.copyWith(
                                  color: o.value == selected
                                      ? c.accentOnFill
                                      : c.labelPrimary,
                                ),
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
  const GlassTabBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<NavigationDestination> destinations;

  /// The height the bar takes at the default text size, margins included, for screens that scroll beneath it.
  static const double height = 66;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: height,
      child: GlassSurface(
        radius: Radii.pill,
        padding: const EdgeInsets.all(Space.xxs),
        // NavigationBar's SafeArea would otherwise add the status bar and home indicator insets inside the pill.
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: NavigationBar(
              height: 58,
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelected,
              destinations: destinations,
            ),
          ),
        ),
      ),
    );
  }
}

/// [primary] and [secondary] on one line, the primary taking the room that is left; or one above the other at full
/// width when the two would not fit on one line, as with large text on a small phone.
class SideBySide extends MultiChildRenderObjectWidget {
  SideBySide({
    super.key,
    required Widget primary,
    required Widget secondary,
    this.gap = Space.xs,
  }) : super(children: [primary, secondary]);

  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSideBySide(gap, Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderSideBySide)
      ..gap = gap
      ..textDirection = Directionality.of(context);
  }
}

class _SideBySideData extends ContainerBoxParentData<RenderBox> {}

class _RenderSideBySide extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SideBySideData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SideBySideData> {
  _RenderSideBySide(this._gap, this._textDirection);

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SideBySideData) {
      child.parentData = _SideBySideData();
    }
  }

  RenderBox get _primary => firstChild!;
  RenderBox get _secondary => lastChild!;

  bool _fits(double width) =>
      _primary.getMaxIntrinsicWidth(double.infinity) +
          _gap +
          _secondary.getMaxIntrinsicWidth(double.infinity) <=
      width;

  Size _arrange(
    BoxConstraints constraints,
    ChildLayouter lay, {
    bool place = false,
  }) {
    final width = constraints.maxWidth;
    if (!_fits(width)) {
      final a = lay(_primary, BoxConstraints.tightFor(width: width));
      final b = lay(_secondary, BoxConstraints.tightFor(width: width));
      if (place) {
        _at(_primary, Offset.zero);
        _at(_secondary, Offset(0, a.height + _gap));
      }
      return constraints.constrain(Size(width, a.height + _gap + b.height));
    }
    final b = lay(_secondary, const BoxConstraints());
    final a = lay(
      _primary,
      BoxConstraints.tightFor(
        width: width.isFinite
            ? width - _gap - b.width
            : _primary.getMaxIntrinsicWidth(double.infinity),
      ),
    );
    final height = math.max(a.height, b.height);
    if (place) {
      final ltr = _textDirection == TextDirection.ltr;
      _at(_primary, Offset(ltr ? 0 : b.width + _gap, (height - a.height) / 2));
      _at(
        _secondary,
        Offset(ltr ? a.width + _gap : 0, (height - b.height) / 2),
      );
    }
    return constraints.constrain(Size(a.width + _gap + b.width, height));
  }

  void _at(RenderBox child, Offset offset) =>
      (child.parentData! as _SideBySideData).offset = offset;

  @override
  void performLayout() {
    size = _arrange(constraints, ChildLayoutHelper.layoutChild, place: true);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _arrange(constraints, ChildLayoutHelper.dryLayoutChild);

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _primary.getMinIntrinsicWidth(height),
    _secondary.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _primary.getMaxIntrinsicWidth(height) +
      _gap +
      _secondary.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) => _fits(width)
      ? math.max(
          _primary.getMinIntrinsicHeight(width),
          _secondary.getMinIntrinsicHeight(width),
        )
      : _primary.getMinIntrinsicHeight(width) +
            _gap +
            _secondary.getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _fits(width)
      ? math.max(
          _primary.getMaxIntrinsicHeight(width),
          _secondary.getMaxIntrinsicHeight(width),
        )
      : _primary.getMaxIntrinsicHeight(width) +
            _gap +
            _secondary.getMaxIntrinsicHeight(width);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToHighestActualBaseline(baseline);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
