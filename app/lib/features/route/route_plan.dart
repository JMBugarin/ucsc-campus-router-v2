import '../location/location_service.dart';

/// A walk from where the student is to the best door of a class's building.
class RoutePlan {
  const RoutePlan({
    required this.start,
    required this.path,
    required this.door,
    required this.walkM,
    required this.indoorM,
    required this.buildingName,
    required this.room,
    this.floor,
    this.note,
  });

  final GeoPoint start;

  /// The walkable path the router found. It runs between the nearest path points to the start and
  /// the door, so it can stop a little short of each.
  final List<GeoPoint> path;
  final GeoPoint door;
  final double walkM;

  /// Straight-line distance from the door to the room itself (0 when the room's spot is unknown).
  final double indoorM;
  final String buildingName;
  final String room;
  final String? floor;
  final String? note;

  /// Same rule as the server's "Today" walk time (1.3 m/s, rounded up).
  int get minutes => ((walkM + indoorM) / 1.3 / 60).ceil();

  factory RoutePlan.fromJson(Map<String, dynamic> json, {required GeoPoint start}) {
    final astar = json['astar'] as Map<String, dynamic>;
    if (astar['found'] != true) {
      throw const FormatException('no route');
    }
    final room = json['room'] as Map<String, dynamic>;
    final door = room['entrance'] as Map<String, dynamic>;
    final floor = room['floor'];
    return RoutePlan(
      start: start,
      path: [
        for (final p in astar['path'] as List) GeoPoint(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()),
      ],
      door: GeoPoint((door['lat'] as num).toDouble(), (door['lon'] as num).toDouble()),
      walkM: (room['walk_m'] as num).toDouble(),
      indoorM: (room['indoor_m'] as num).toDouble(),
      buildingName: (room['building_name'] as String?) ?? '',
      room: (room['room'] as String?) ?? '',
      floor: floor == null ? null : '$floor',
      note: room['note'] as String?,
    );
  }
}
