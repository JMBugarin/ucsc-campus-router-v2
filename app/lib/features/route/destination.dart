import '../location/location_service.dart';

/// Somewhere to walk to. A schedule row, a searched place and a dropped pin all become one of these.
sealed class Destination {
  const Destination();

  /// What to show as the title of the route.
  String get label;

  /// The query the server's `/api/route_to` understands, apart from the start point.
  Map<String, String> get query;
}

/// A room or building named the way the server resolves it, such as `Kresge Acad 3201`.
class RoomDestination extends Destination {
  const RoomDestination(this.location);

  final String location;

  @override
  String get label => location;

  @override
  Map<String, String> get query => {'room': location};

  @override
  bool operator ==(Object other) =>
      other is RoomDestination && other.location == location;

  @override
  int get hashCode => location.hashCode;
}

/// A spot on the map with no building or room behind it.
class PointDestination extends Destination {
  const PointDestination(this.point, {this.name = ''});

  final GeoPoint point;
  final String name;

  @override
  String get label => name.isEmpty ? 'Dropped pin' : name;

  @override
  Map<String, String> get query => {
    'to': '${point.lat},${point.lon}',
    if (name.isNotEmpty) 'name': name,
  };

  @override
  bool operator ==(Object other) =>
      other is PointDestination && other.point == point && other.name == name;

  @override
  int get hashCode => Object.hash(point, name);
}
