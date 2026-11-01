import '../../campus/campus.dart';
import '../../campus/geo_point.dart';

/// One search answer: a building, or a room inside one.
class Place {
  const Place({
    required this.buildingId,
    required this.buildingName,
    required this.label,
    required this.query,
    this.room,
    this.roomKnown,
    this.floor,
    this.point,
  });

  final String buildingId;
  final String buildingName;

  /// Building name plus room, for showing.
  final String label;

  /// A schedule-style location that resolves back to this place, such as `Kresge College Academic Building 3201`.
  final String query;
  final String? room;

  /// False when the building lists its rooms and this one is not among them.
  final bool? roomKnown;
  final String? floor;
  final GeoPoint? point;

  bool get isRoom => room != null;

  factory Place.fromHit(SearchHit hit) => Place(
    buildingId: hit.buildingId,
    buildingName: hit.buildingName,
    label: hit.label,
    query: hit.query,
    room: hit.room,
    roomKnown: hit.roomKnown,
    floor: hit.floor,
    point: hit.point,
  );

  factory Place.fromJson(Map<String, dynamic> json) {
    final point = json['point'] as Map<String, dynamic>?;
    return Place(
      buildingId: json['building_id'] as String,
      buildingName: json['building_name'] as String,
      label: json['label'] as String,
      query: json['query'] as String,
      room: json['room'] as String?,
      roomKnown: json['room_known'] as bool?,
      floor: json['floor'] as String?,
      point: point == null
          ? null
          : GeoPoint(
              (point['lat'] as num).toDouble(),
              (point['lon'] as num).toDouble(),
            ),
    );
  }
}

/// The place a schedule-style [location] (such as `Kresge Acad 3201`) names, or null when it is online, to be
/// announced, unknown or has no position yet.
Place? placeFor(Campus campus, String location) {
  final r = campus.resolve(location);
  if (r.kind != 'building') return null;
  final building = campus.buildings[r.buildingId]!;
  final spot = r.roomPoint?.point ?? building.centroid;
  return Place(
    buildingId: building.id,
    buildingName: building.name,
    label: r.room == null ? building.name : '${building.name} ${r.room}',
    query: location,
    room: r.room,
    roomKnown: r.roomKnown,
    floor: r.floor,
    point: spot,
  );
}
