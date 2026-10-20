import 'package:flutter/material.dart';

import 'tokens.dart';

/// The gold destination pin: the one place gold appears.
class DestinationPin extends StatelessWidget {
  const DestinationPin({super.key, this.size = 40, this.label});

  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: label ?? 'Destination',
      child: ExcludeSemantics(
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Icon(Icons.location_on, size: size, color: c.markerOutline),
            Icon(Icons.location_on, size: size - 6, color: c.markerDestination),
          ],
        ),
      ),
    );
  }
}

/// Where you are: a blue dot with a ring.
class UserDot extends StatelessWidget {
  const UserDot({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'You are here',
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.userDot,
          border: Border.all(color: c.surfaceContent, width: 3),
          boxShadow: Elevation.raised,
        ),
        child: const SizedBox.square(dimension: 22),
      ),
    );
  }
}

/// A campus bus stop or parking area to arrive at.
class EntryMarker extends StatelessWidget {
  const EntryMarker({super.key, required this.name, this.icon = Icons.directions_bus_outlined});

  final String name;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: name,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.accentFill,
          border: Border.all(color: c.surfaceContent, width: 3),
          boxShadow: Elevation.raised,
        ),
        child: SizedBox.square(dimension: 40, child: Icon(icon, color: c.accentOnFill, size: 22)),
      ),
    );
  }
}
