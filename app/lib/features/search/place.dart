import '../location/location_service.dart';

/// One answer from the server's `/api/search`: a building, or a room inside one.
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

  /// A schedule-style location that the server routes to, such as `Kresge College Academic Building 3201`.
  final String query;
  final String? room;

  /// False when the building lists its rooms and this one is not among them.
  final bool? roomKnown;
  final String? floor;
  final GeoPoint? point;

  bool get isRoom => room != null;

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
      point: point == null ? null : GeoPoint((point['lat'] as num).toDouble(), (point['lon'] as num).toDouble()),
    );
  }
}
