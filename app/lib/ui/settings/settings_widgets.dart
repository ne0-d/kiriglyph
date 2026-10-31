import 'package:flutter/material.dart';

import 'package:kiriglyph/theme/app_theme.dart';

/// A titled group of rows in one rounded surface with thin dividers, the way
/// GNOME's preferences pages lay out a list of settings.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fill = Color.alphaBlend(
      scheme.onSurface.withValues(alpha: 0.06),
      scheme.surface,
    );
    final rows = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        rows.add(
          Divider(
            height: 1,
            thickness: 1,
            color: scheme.onSurface.withValues(alpha: 0.08),
          ),
        );
      }
      rows.add(children[index]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, AppSpacing.sm),
            child: Semantics(
              header: true,
              child: Text(
                title!,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.surface),
          child: ColoredBox(
            color: fill,
            child: Column(children: rows),
          ),
        ),
      ],
    );
  }
}

/// One row: a title, an optional second line, and a control on the right.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.details,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Color? subtitleColor;

  /// Extra content under the subtitle, such as a command to copy.
  final Widget? details;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.bodyLarge),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color:
                                  subtitleColor ??
                                  theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ?details,
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum SettingsBannerTone { info, error }

/// A short notice above the groups, for what needs the user's attention.
class SettingsBanner extends StatelessWidget {
  const SettingsBanner({
    super.key,
    required this.message,
    this.tone = SettingsBannerTone.info,
  });

  final String message;
  final SettingsBannerTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final error = tone == SettingsBannerTone.error;
    final color = error ? scheme.error : scheme.primary;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadii.surface),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                error ? Icons.error_outline : Icons.info_outline,
                color: color,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
