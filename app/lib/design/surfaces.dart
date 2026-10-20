import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'glass.dart';
import 'tokens.dart';
import 'type.dart';

/// A status that always carries a word, never colour alone: `ok`, `tight`, `late` or anything else for `?`.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = switch (status) {
      'ok' => 'OK',
      'tight' => 'Tight',
      'late' => 'Late',
      _ => '?',
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: c.statusFill(status), borderRadius: BorderRadius.circular(Radii.pill)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xxs),
        child: Text(label, style: AppText.footnote.copyWith(color: c.statusOn(status), fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// A small pill with a word in it, such as Next or Now.
class RoleChip extends StatelessWidget {
  const RoleChip({super.key, required this.label, this.fill, this.onFill});

  final String label;
  final Color? fill;
  final Color? onFill;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: fill ?? c.accentFill, borderRadius: BorderRadius.circular(Radii.pill)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xxs),
        child: Text(label, style: AppText.footnote.copyWith(color: onFill ?? c.accentOnFill, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

enum ClassRole { next, now, later }

/// One class on a solid surface: when, what, where, and for the next one how to get there. [arrival] and
/// [flag] are optional lines, [trailing] sits beside the room, and [action] is a solid prominent button.
class ClassCard extends StatelessWidget {
  const ClassCard({
    super.key,
    required this.role,
    required this.time,
    required this.title,
    required this.room,
    this.header,
    this.arrival,
    this.arrivalIcon = Icons.directions_walk,
    this.flag,
    this.trailing,
    this.action,
  });

  final ClassRole role;
  final String time;
  final String title;
  final String room;

  /// Something above the time, such as how this class follows the one before it.
  final Widget? header;
  final String? arrival;
  final IconData arrivalIcon;
  final String? flag;
  final Widget? trailing;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (borderColor, borderWidth) = switch (role) {
      ClassRole.next => (c.accentFill, 2.0),
      ClassRole.now => (c.statusOkFill, 2.0),
      ClassRole.later => (c.separator, 1.0),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceContent,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header != null) ...[header!, const SizedBox(height: Space.xs)],
            Row(
              children: [
                Expanded(child: Text(time, style: AppText.subhead.copyWith(color: c.labelSecondary))),
                if (role == ClassRole.next) const RoleChip(label: 'Next'),
                if (role == ClassRole.now) RoleChip(label: 'Now', fill: c.statusOkFill, onFill: c.statusOkOn),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(title, style: AppText.headline.copyWith(color: c.labelPrimary)),
            const SizedBox(height: Space.xxs),
            Row(
              children: [
                Expanded(child: Text(room, style: AppText.callout.copyWith(color: c.labelSecondary))),
                ?trailing,
              ],
            ),
            if (arrival != null) ...[
              const SizedBox(height: Space.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(arrivalIcon, color: c.accentText),
                  const SizedBox(width: Space.xs),
                  Expanded(child: Text(arrival!, style: AppText.headline.copyWith(color: c.accentText))),
                ],
              ),
            ],
            if (flag != null) ...[
              const SizedBox(height: Space.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: c.statusTightFill),
                  const SizedBox(width: Space.xs),
                  Expanded(child: Text(flag!, style: AppText.subhead.copyWith(color: c.labelPrimary))),
                ],
              ),
            ],
            if (action != null) ...[const SizedBox(height: Space.sm), action!],
          ],
        ),
      ),
    );
  }
}

enum BannerKind { offline, stale, updating }

/// Says plainly that what is on screen comes from the phone's memory: the server cannot be reached, the
/// saved times are old, or it is asking again.
class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.kind, required this.title, required this.body, this.actionLabel, this.onAction});

  final BannerKind kind;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final icon = switch (kind) {
      BannerKind.offline => Icons.cloud_off_outlined,
      BannerKind.stale => Icons.schedule,
      BannerKind.updating => Icons.sync,
    };
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: c.bannerFill, borderRadius: BorderRadius.circular(Radii.lg)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: c.accentText),
                  const SizedBox(width: Space.xs),
                  Expanded(child: Text(title, style: AppText.headline.copyWith(color: c.labelPrimary))),
                ],
              ),
              const SizedBox(height: Space.xs),
              Text(body, style: AppText.subhead.copyWith(color: c.labelPrimary)),
              if (kind == BannerKind.updating) ...[const SizedBox(height: Space.xs), const LinearProgressIndicator()],
              if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a screen shows while a server that has sat idle wakes up: a progress bar and the reason. It is glass
/// over the map and a solid card on a list.
class WakingCard extends ConsumerWidget {
  const WakingCard({
    super.key,
    this.glass = false,
    this.title = 'Waking the server',
    this.body = 'The free host sleeps when idle and can take up to a minute. Your saved classes are still here.',
  });

  final bool glass;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final content = Padding(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: Space.xs),
          Semantics(liveRegion: true, child: Text(title, style: AppText.headline.copyWith(color: c.labelPrimary))),
          const SizedBox(height: Space.xs),
          Text(body, style: AppText.subhead.copyWith(color: c.labelSecondary)),
        ],
      ),
    );
    if (glass) return GlassSurface(child: content);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceContent,
        borderRadius: BorderRadius.circular(Radii.glass),
        border: Border.all(color: c.separator),
      ),
      child: content,
    );
  }
}

/// A row in a solid list, such as a search result. [flagged] puts a warning with a sentence under the title.
class ListRow extends StatelessWidget {
  const ListRow({super.key, required this.title, this.subtitle, this.icon = Icons.place_outlined, this.flagged = false, this.onTap});

  final String title;
  final String? subtitle;
  final IconData icon;
  final bool flagged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surfaceContent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
            child: Row(
              children: [
                Icon(icon, color: c.labelSecondary),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.body.copyWith(color: c.labelPrimary)),
                      if (subtitle != null)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (flagged) ...[Icon(Icons.warning_amber_rounded, size: 18, color: c.statusTightFill), const SizedBox(width: Space.xxs)],
                            Expanded(
                              child: Text(subtitle!, style: AppText.subhead.copyWith(color: flagged ? c.labelPrimary : c.labelSecondary)),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (onTap != null) Icon(Icons.chevron_right, color: c.labelTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
