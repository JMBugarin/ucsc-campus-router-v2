import 'dart:async';

import 'package:flutter/material.dart';

/// Goes under a spinner. If the wait drags on it explains why: a hosted server that has sat idle
/// needs up to a minute to wake.
class WakingNote extends StatefulWidget {
  const WakingNote({super.key, this.after = const Duration(seconds: 4)});

  final Duration after;

  @override
  State<WakingNote> createState() => _WakingNoteState();
}

class _WakingNoteState extends State<WakingNote> {
  Timer? _timer;
  var _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.after, () => setState(() => _visible = true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Still working. The server may be waking up after sitting idle, which can take up to a minute.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}
