import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../settings/settings.dart';
import 'today_controller.dart';
import 'today_models.dart';
import 'today_text.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverUrl = ref.watch(settingsProvider.select((s) => s.serverUrl));
    final today = ref.watch(todayProvider);

    Future<void> refresh() => ref.read(todayProvider.notifier).refresh();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: serverUrl.isEmpty ? null : refresh),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (serverUrl.isEmpty)
              _MessageCard(
                icon: Icons.cloud_off_outlined,
                title: 'Connect to the server',
                body: 'The app needs the address of the campus router server to work out your walks.',
                actionLabel: 'Open Settings',
                onAction: () => ref.read(selectedTabProvider.notifier).select(tabSettings),
              )
            else
              today.when(
                loading: () => const _LoadingCard(),
                error: (error, _) => _MessageCard(
                  icon: Icons.error_outline,
                  title: "Couldn't work out your day",
                  body: error is ApiException ? error.message : 'Something went wrong. Try again.',
                  actionLabel: 'Try again',
                  onAction: refresh,
                ),
                data: (data) => _TodayBody(data: data),
              ),
          ],
        ),
      ),
    );
  }
}

class _TodayBody extends ConsumerWidget {
  const _TodayBody({required this.data});

  final TodayData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = data.analysis;
    if (analysis == null) {
      return _MessageCard(
        icon: Icons.calendar_month_outlined,
        title: 'Add your classes',
        body: 'Paste your MyUCSC schedule, import a calendar file, or add classes by hand. Then this '
            'screen shows what is next, how long the walk is, and whether you have time.',
        actionLabel: 'Go to Schedule',
        onAction: () => ref.read(selectedTabProvider.notifier).select(tabSchedule),
      );
    }

    final walk = walkText(analysis);
    final notes = [if (data.locationProblem != null) data.locationProblem!, ...analysis.notes];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(todaySummary(analysis), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (analysis.banner != null) _Banner(banner: analysis.banner!),
        if (walk != null) _WalkCard(status: walk.status, text: walk.text),
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(note, style: Theme.of(context).textTheme.bodyMedium),
          ),
        if (analysis.today.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text("Today's classes", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final t in analysis.today) _TimelineTile(classTime: t, analysis: analysis),
        ],
      ],
    );
  }
}

/// A status chip that never relies on colour alone: it always carries a word.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'ok' => ('OK', Colors.green.shade700),
      'tight' => ('Tight', Colors.orange.shade800),
      'late' => ('Late', Colors.red.shade700),
      _ => ('?', Colors.grey.shade700),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class _WalkCard extends StatelessWidget {
  const _WalkCard({required this.status, required this.text});

  final String status;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusChip(status: status),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.banner});

  final LeaveBanner banner;

  @override
  Widget build(BuildContext context) {
    final color = banner.late ? Colors.red.shade700 : Colors.orange.shade800;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            const Icon(Icons.directions_walk, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(banner.text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.classTime, required this.analysis});

  final ClassTime classTime;
  final Analysis analysis;

  @override
  Widget build(BuildContext context) {
    final isNow = analysis.current?.start == classTime.start;
    final isNext = analysis.next?.isToday == true && analysis.next?.start == classTime.start;
    final scheme = Theme.of(context).colorScheme;
    final transition = transitionText(classTime);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isNow ? scheme.primary : (isNext ? scheme.tertiary : scheme.outlineVariant),
          width: isNow || isNext ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (transition != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusChip(status: transition.status),
                    const SizedBox(width: 8),
                    Expanded(child: Text(transition.text, style: Theme.of(context).textTheme.bodySmall)),
                  ],
                ),
              ),
            Text(
              '${clockFromIso(classTime.start)}–${clockFromIso(classTime.end)}'
              '${isNow ? '  ·  now' : (isNext ? '  ·  next' : '')}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 2),
            Text(classTime.label, style: Theme.of(context).textTheme.titleMedium),
            Text(classTime.location),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(body),
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(),
            SizedBox(height: 12),
            Text('Working out your day…'),
            SizedBox(height: 4),
            Text(
              'If the server has been idle this can take up to a minute while it wakes up.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
