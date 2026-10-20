import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucsc_router/design/accessibility_environment.dart';
import 'package:ucsc_router/design/controls.dart';
import 'package:ucsc_router/design/glass.dart';
import 'package:ucsc_router/design/surfaces.dart';
import 'package:ucsc_router/design/theme.dart';

class FakeAccessibility implements AccessibilityEnvironment {
  FakeAccessibility([this.reduce = false]);

  bool reduce;
  void Function(bool)? onChange;

  @override
  Future<bool> reduceTransparency() async => reduce;

  @override
  void listen(void Function(bool reduceTransparency) onChange) => this.onChange = onChange;
}

enum Look { light, dark, large, solid }

Future<void> pumpLook(
  WidgetTester tester,
  Widget child, {
  Look look = Look.light,
  FakeAccessibility? accessibility,
  bool highContrast = false,
  bool platformGlass = true,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      glassSupportedProvider.overrideWithValue(platformGlass && look != Look.solid),
      accessibilityEnvironmentProvider.overrideWithValue(accessibility ?? FakeAccessibility()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: look == Look.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(look == Look.large ? 3 : 1),
          highContrast: highContrast,
        ),
        child: app!,
      ),
      home: Scaffold(
        body: Container(
          color: look == Look.dark ? const Color(0xFF2B4033) : const Color(0xFFCFE3B9),
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(child: child),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

int blurs(WidgetTester tester) => find.byType(BackdropFilter).evaluate().length;

void main() {
  group('the glass or solid decision', () {
    test('iOS 26 and later draw glass; older iOS and other platforms do not', () {
      expect(osSupportsGlass(platform: TargetPlatform.iOS, version: 'Version 27.0 (Build 24A5)'), isTrue);
      expect(osSupportsGlass(platform: TargetPlatform.iOS, version: 'Version 26.1 (Build 23B)'), isTrue);
      expect(osSupportsGlass(platform: TargetPlatform.iOS, version: 'Version 18.4 (Build 22E)'), isFalse);
      expect(osSupportsGlass(platform: TargetPlatform.iOS, version: 'unreadable'), isFalse);
      expect(osSupportsGlass(platform: TargetPlatform.android, version: 'Version 30'), isFalse);
    });

    testWidgets('Reduce Transparency, read from the phone, turns glass into solid and back', (tester) async {
      final fake = FakeAccessibility(true);
      await pumpLook(tester, const GlassSurface(child: Text('x')), accessibility: fake);
      expect(blurs(tester), 0);
      fake.onChange!(false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(blurs(tester), 1);
      fake.onChange!(true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(blurs(tester), 0);
    });

    testWidgets('Increase Contrast turns glass into solid', (tester) async {
      await pumpLook(tester, const GlassSurface(child: Text('x')), highContrast: true);
      expect(blurs(tester), 0);
    });

    testWidgets('a platform without glass draws solid', (tester) async {
      await pumpLook(tester, const GlassSurface(child: Text('x')), platformGlass: false);
      expect(blurs(tester), 0);
    });

    testWidgets('glass is never stacked: inside glass a surface does not blur again', (tester) async {
      await pumpLook(
        tester,
        const GlassSurface(child: GlassSurface(child: GlassSurface(strong: true, child: Text('deep')))),
      );
      expect(blurs(tester), 1);
      expect(find.text('deep'), findsOneWidget);
    });

    testWidgets('the platform channel answers, and a missing one reads as Reduce Transparency off', (tester) async {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(ChannelAccessibilityEnvironment.channel, (call) async => call.method == 'reduceTransparency' ? true : null);
      expect(await ChannelAccessibilityEnvironment().reduceTransparency(), isTrue);
      messenger.setMockMethodCallHandler(ChannelAccessibilityEnvironment.channel, (call) async => throw MissingPluginException());
      expect(await ChannelAccessibilityEnvironment().reduceTransparency(), isFalse);
      messenger.setMockMethodCallHandler(ChannelAccessibilityEnvironment.channel, null);
    });

    testWidgets('a change pushed from the phone reaches the listener', (tester) async {
      bool? seen;
      ChannelAccessibilityEnvironment().listen((on) => seen = on);
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      await messenger.handlePlatformMessage(
        'ucsc_router/accessibility',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('reduceTransparencyChanged', true)),
        (_) {},
      );
      expect(seen, isTrue);
    });
  });

  for (final look in Look.values) {
    group('components in ${look.name}', () {
      final glass = look != Look.solid;

      testWidgets('GlassSurface keeps its shape and content', (tester) async {
        await pumpLook(tester, const SizedBox(width: 200, height: 80, child: GlassSurface(strong: true, child: Center(child: Text('Card')))), look: look);
        expect(find.text('Card'), findsOneWidget);
        expect(blurs(tester), glass ? 1 : 0);
        expect(tester.takeException(), isNull);
      });

      testWidgets('GlassButton: label, tap, 50 pt high, default and prominent', (tester) async {
        var taps = 0;
        await pumpLook(
          tester,
          Column(children: [
            GlassButton(label: 'Show route', icon: Icons.route, onPressed: () => taps++),
            const SizedBox(height: 12),
            GlassButton(label: 'Get to campus with Transit', icon: Icons.directions_bus, prominent: true, expand: true, onPressed: () => taps += 10),
            const SizedBox(height: 12),
            const GlassButton(label: 'Off', onPressed: null),
          ]),
          look: look,
        );
        for (final label in ['Show route', 'Get to campus with Transit']) {
          final box = tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first);
          expect(box.height, greaterThanOrEqualTo(50));
        }
        await tester.tap(find.text('Show route'));
        await tester.tap(find.text('Get to campus with Transit'));
        expect(taps, 11);
        expect(tester.getSemantics(find.text('Show route')).label, 'Show route');
        expect(tester.takeException(), isNull);
      });

      testWidgets('GlassIconButton: tooltip, at least 44 pt, tap', (tester) async {
        var taps = 0;
        await pumpLook(tester, GlassIconButton(icon: Icons.my_location, tooltip: 'Locate me', onPressed: () => taps++), look: look);
        expect(find.byTooltip('Locate me'), findsOneWidget);
        expect(tester.getSize(find.byType(GlassIconButton)).width, greaterThanOrEqualTo(44));
        await tester.tap(find.byTooltip('Locate me'));
        expect(taps, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('GlassSearchField: hint, typing, clear', (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final typed = <String>[];
        var cleared = 0;
        await pumpLook(tester, GlassSearchField(controller: controller, onChanged: typed.add, onClear: () => cleared++), look: look);
        expect(find.text('Search a room or building'), findsOneWidget);
        expect(find.byTooltip('Clear search'), findsNothing);
        await tester.enterText(find.byType(TextField), 'BE 152');
        await tester.pump(const Duration(milliseconds: 300));
        expect(typed, ['BE 152']);
        expect(tester.getSize(find.byType(GlassSearchField)).height, greaterThanOrEqualTo(50));
        await tester.tap(find.byTooltip('Clear search'));
        expect(cleared, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('ModeSelector: four segments, the selected one is announced, each at least 44 pt', (tester) async {
        String? picked;
        await pumpLook(
          tester,
          ModeSelector<String>(
            options: const [
              ModeOption(value: 'walk', label: 'Walk', icon: Icons.directions_walk),
              ModeOption(value: 'bike', label: 'Bike', icon: Icons.directions_bike),
              ModeOption(value: 'drive', label: 'Drive', icon: Icons.directions_car),
              ModeOption(value: 'transit', label: 'Transit', icon: Icons.directions_bus),
            ],
            selected: 'bike',
            onSelected: (v) => picked = v,
          ),
          look: look,
        );
        expect(tester.getSemantics(find.text('Bike')).flagsCollection.isSelected.toBoolOrNull(), isTrue);
        expect(tester.getSize(find.ancestor(of: find.text('Walk'), matching: find.byType(InkWell)).first).height, greaterThanOrEqualTo(44));
        await tester.tap(find.text('Transit'));
        expect(picked, 'transit');
        expect(tester.takeException(), isNull);
      });

      testWidgets('GlassTabBar: tabs keep their semantics and one blur', (tester) async {
        var selected = 0;
        await pumpLook(
          tester,
          StatefulBuilder(
            builder: (context, set) => GlassTabBar(
              selectedIndex: selected,
              onSelected: (i) => set(() => selected = i),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
                NavigationDestination(icon: Icon(Icons.today_outlined), label: 'Today'),
                NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Schedule'),
                NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
              ],
            ),
          ),
          look: look,
        );
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(blurs(tester), glass ? 1 : 0);
        await tester.tap(find.text('Today'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(selected, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('StatusChip always says a word', (tester) async {
        await pumpLook(tester, const Column(children: [StatusChip(status: 'ok'), StatusChip(status: 'tight'), StatusChip(status: 'late'), StatusChip(status: 'unknown')]), look: look);
        for (final word in ['OK', 'Tight', 'Late', '?']) {
          expect(find.text(word), findsOneWidget);
        }
      });

      testWidgets('ClassCard in each role, with arrival, flag, trailing and action', (tester) async {
        await pumpLook(
          tester,
          Column(children: [
            ClassCard(
              role: ClassRole.next,
              time: '3:45 to 4:50 PM',
              title: 'CSE 12 Lecture',
              room: 'Kresge Acad 3201 · Kresge College Academic Building',
              arrival: 'Be at Rachel Carson College bus stop by 3:21 PM',
              arrivalIcon: Icons.directions_bus_outlined,
              trailing: const Icon(Icons.map_outlined),
              action: FilledButton(onPressed: () {}, child: const Text('Get to campus with Transit')),
            ),
            const ClassCard(role: ClassRole.now, time: '2:00 to 3:05 PM', title: 'MATH 19B', room: 'Thim Lecture 003'),
            const ClassCard(role: ClassRole.later, time: '5:20 to 6:25 PM', title: 'PHYS 6A', room: 'Soc Sci 2 075', flag: "We can't find this room on the campus map."),
          ]),
          look: look,
        );
        expect(find.text('Next'), findsOneWidget);
        expect(find.text('Now'), findsOneWidget);
        expect(find.text("We can't find this room on the campus map."), findsOneWidget);
        expect(find.text('Get to campus with Transit'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('StatusBanner: offline with a button, stale, updating with progress', (tester) async {
        var again = 0;
        await pumpLook(
          tester,
          Column(children: [
            StatusBanner(kind: BannerKind.offline, title: 'Offline', body: "Can't reach the server, so this is worked out on your phone.", actionLabel: 'Try again', onAction: () => again++),
            const StatusBanner(kind: BannerKind.stale, title: 'Saved walk times', body: 'These walk times are over a week old.'),
            const StatusBanner(kind: BannerKind.updating, title: 'Updating', body: 'Showing what is saved on this phone while the server answers.'),
          ]),
          look: look,
        );
        await tester.ensureVisible(find.text('Try again'));
        await tester.tap(find.text('Try again'));
        expect(again, 1);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('WakingCard: solid on a list, glass over a map', (tester) async {
        await pumpLook(tester, const Column(children: [WakingCard(), SizedBox(height: 12), WakingCard(glass: true)]), look: look);
        expect(find.text('Waking the server'), findsNWidgets(2));
        expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
        expect(blurs(tester), glass ? 1 : 0);
        expect(tester.takeException(), isNull);
      });

      testWidgets('ListRow: title, subtitle, flagged warning, tap', (tester) async {
        var taps = 0;
        await pumpLook(
          tester,
          Column(children: [
            ListRow(title: 'Jack Baskin Engineering 152', subtitle: 'Floor 1', onTap: () => taps++),
            const ListRow(title: 'Jack Baskin Engineering 156', subtitle: "Not on the building's room list", flagged: true),
          ]),
          look: look,
        );
        expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
        await tester.tap(find.text('Jack Baskin Engineering 152'));
        expect(taps, 1);
        expect(tester.getSize(find.byType(ListRow).first).height, greaterThanOrEqualTo(56));
        expect(tester.takeException(), isNull);
      });
    });
  }
}
