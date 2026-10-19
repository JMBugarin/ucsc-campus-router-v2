import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where map tiles come from and what the map must credit.
class TileSource {
  const TileSource({required this.urlTemplate, required this.attribution});

  final String urlTemplate;
  final String attribution;
}

const _osm = TileSource(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  attribution: '© OpenStreetMap contributors',
);

/// `--dart-define=TILE_PROVIDER=maptiler|stadia` with `--dart-define=TILE_KEY=...` picks a hosted
/// provider. Without a key (or with an unknown provider) it falls back to OpenStreetMap's public
/// tile server, which is fine for development but not for wide release. Keys stay out of the repo:
/// pass them with `--dart-define-from-file=dart_defines.json` (git-ignored).
TileSource tileSourceFor(String provider, String key) {
  if (key.isEmpty) return _osm;
  switch (provider) {
    case 'maptiler':
      return TileSource(
        urlTemplate: 'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=$key',
        attribution: '© MapTiler © OpenStreetMap contributors',
      );
    case 'stadia':
      return TileSource(
        urlTemplate: 'https://tiles.stadiamaps.com/tiles/osm_bright/{z}/{x}/{y}.png?api_key=$key',
        attribution: '© Stadia Maps © OpenMapTiles © OpenStreetMap contributors',
      );
    default:
      return _osm;
  }
}

final tileSource = tileSourceFor(
  const String.fromEnvironment('TILE_PROVIDER'),
  const String.fromEnvironment('TILE_KEY'),
);

/// Whether to draw tiles at all. Tests turn this off so nothing touches the network.
final showMapTilesProvider = Provider<bool>((ref) => true);

/// The base map for every map screen.
class BaseMapLayer extends ConsumerWidget {
  const BaseMapLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(showMapTilesProvider)) return const SizedBox.shrink();
    return TileLayer(
      urlTemplate: tileSource.urlTemplate,
      userAgentPackageName: 'io.github.jmbugarin.ucsc_router',
    );
  }
}

class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});

  @override
  Widget build(BuildContext context) =>
      RichAttributionWidget(attributions: [TextSourceAttribution(tileSource.attribution)]);
}
