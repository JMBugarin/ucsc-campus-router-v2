import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/floating_bar.dart';
import '../../design/surfaces.dart';
import '../../design/tokens.dart';
import '../activity/activity.dart';
import '../reminders/reminder.dart';
import '../reminders/reminder_controller.dart';
import '../reminders/reminder_scheduler.dart';
import 'settings.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _reminderMessage;

  Future<void> _setReminders(bool on) async {
    if (on) {
      final allowed = await ref
          .read(reminderSchedulerProvider)
          .requestPermission();
      if (!mounted) return;
      if (!allowed) {
        setState(
          () => _reminderMessage =
              "Notifications are blocked for this app. Allow them in the phone's settings.",
        );
        return;
      }
    }
    setState(() => _reminderMessage = null);
    await ref.read(settingsProvider.notifier).setRemindersOn(on);
  }

  Future<void> _sendTest() async {
    await ref
        .read(reminderSchedulerProvider)
        .show(
          const Reminder(
            stage: 'class',
            key: 'test',
            inSeconds: 0,
            title: 'XYZ 10 Lecture in 10 min (test)',
            body: 'This is what a class reminder looks like.',
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final planProblem = ref.watch(reminderControllerProvider).value;
    final counting = ref.watch(activitySenderProvider) != null;
    final activity = ref.watch(activityProvider);
    final theme = Theme.of(context);
    Widget line(String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text, style: theme.textTheme.bodyMedium),
    );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            Space.md,
            Space.xs,
            Space.md,
            Space.md + FloatingBarInset.of(context),
          ),
          children: [
            const LargeTitleHeader(title: 'Settings'),
            const SizedBox(height: Space.sm),
            GroupCard(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Class reminders'),
                  subtitle: const Text(
                    'A notification before each class over the next week, even if the app is closed. They are planned '
                    'whenever the app opens, so open it at least once a week.',
                  ),
                  value: settings.remindersOn,
                  onChanged: _setReminders,
                ),
                if (_reminderMessage != null || planProblem != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _reminderMessage ?? planProblem!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                if (settings.remindersOn)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _sendTest,
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: const Text('Send a test notification'),
                    ),
                  ),
                const Divider(),
                Text(
                  'Remind me before class',
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  'How long before a class starts the reminder comes.',
                  style: theme.textTheme.bodyMedium,
                ),
                DropdownButton<int>(
                  isExpanded: true,
                  value: settings.remindLeadMinutes,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('At the start')),
                    DropdownMenuItem(value: 5, child: Text('5 min')),
                    DropdownMenuItem(value: 10, child: Text('10 min')),
                    DropdownMenuItem(value: 15, child: Text('15 min')),
                    DropdownMenuItem(value: 30, child: Text('30 min')),
                  ],
                  onChanged: (value) => controller.setRemindLead(value ?? 10),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            Semantics(
              header: true,
              child: Text('Your data', style: theme.textTheme.titleMedium),
            ),
            line(
              counting
                  ? 'Your schedule is saved only on this phone. There is no account.'
                  : 'Your schedule is saved only on this phone. There is no account and no server.',
            ),
            line(
              'The app never asks for your location. Walk there hands the destination to your maps app, which finds where you are.',
            ),
            line(
              'When you read a schedule from a picture, the phone reads it and the picture goes nowhere.',
            ),
            line(
              'The map downloads its tiles from a map provider, which sees the area you look at and your network address.',
            ),
            if (counting) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Count my weekly use'),
                subtitle: const Text(
                  'Off unless you turn it on. Once a week, after you find a room or open a class on the map, '
                  'the phone sends a random id and the week, nothing else: no schedule, searches, location or name. '
                  'Turning it off deletes what was sent.',
                ),
                value: activity.on,
                onChanged: ref.read(activityProvider.notifier).setOn,
              ),
              if (activity.participantCode case final code?)
                line('Participant code: $code'),
            ],
            const Divider(height: 32),
            Semantics(
              header: true,
              child: Text('About the data', style: theme.textTheme.titleMedium),
            ),
            line(
              'Not affiliated with or endorsed by UC Santa Cruz. Room names and positions come from the public UCSC '
              'classroom directory and campus map; building outlines and doors are © OpenStreetMap contributors (ODbL). '
              'A pin can be wrong: check the room number on your schedule.',
            ),
          ],
        ),
      ),
    );
  }
}
