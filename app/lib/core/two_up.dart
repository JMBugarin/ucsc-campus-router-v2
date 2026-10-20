import 'package:flutter/material.dart';

/// Two widgets side by side, or one above the other once the text is large enough that they would not fit.
class TwoUp extends StatelessWidget {
  const TwoUp(this.first, this.second, {super.key});

  final Widget first;
  final Widget? second;

  @override
  Widget build(BuildContext context) {
    final buttons = [first, ?second];
    if (MediaQuery.textScalerOf(context).scale(14) > 21) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[if (i > 0) const SizedBox(height: 8), buttons[i]],
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: buttons[i])],
      ],
    );
  }
}
