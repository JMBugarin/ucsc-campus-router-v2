import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/core/tiles.dart';

void main() {
  group('tile source', () {
    test('without a key it uses the public OpenStreetMap server, whatever the provider', () {
      for (final provider in ['', 'maptiler', 'stadia', 'nope']) {
        final source = tileSourceFor(provider, '');
        expect(source.urlTemplate, startsWith('https://tile.openstreetmap.org/'));
        expect(source.attribution, contains('OpenStreetMap'));
      }
    });

    test('a hosted provider gets its key in the address and credits itself and OpenStreetMap', () {
      final maptiler = tileSourceFor('maptiler', 'abc123');
      expect(maptiler.urlTemplate, allOf(startsWith('https://api.maptiler.com/'), contains('{z}/{x}/{y}'), endsWith('key=abc123')));
      expect(maptiler.attribution, allOf(contains('MapTiler'), contains('OpenStreetMap')));

      final stadia = tileSourceFor('stadia', 'k');
      expect(stadia.urlTemplate, allOf(startsWith('https://tiles.stadiamaps.com/'), endsWith('api_key=k')));
      expect(stadia.attribution, allOf(contains('Stadia'), contains('OpenStreetMap')));
    });

    test('an unknown provider with a key falls back rather than sending the key somewhere', () {
      final source = tileSourceFor('someone-else', 'secret');
      expect(source.urlTemplate, isNot(contains('secret')));
    });
  });
}
