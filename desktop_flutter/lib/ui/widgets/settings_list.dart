import 'package:flutter/material.dart';

import '../neko_theme.dart';

/// A titled group of settings rows on a single rounded surface.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    this.title,
    this.description,
    required this.children,
  });

  final String? title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: NekoSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NekoSpace.xs,
                0,
                NekoSpace.xs,
                NekoSpace.sm,
              ),
              child: Text(
                title!,
                style: text.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  if (index > 0)
                    Divider(
                      indent: NekoSpace.lg,
                      endIndent: NekoSpace.lg,
                      color: colors.outlineVariant.withValues(alpha: 0.6),
                    ),
                  children[index],
                ],
              ],
            ),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NekoSpace.xs,
                NekoSpace.sm,
                NekoSpace.xs,
                0,
              ),
              child: Text(description!, style: text.bodySmall),
            ),
        ],
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.enabled = true,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final foreground = destructive ? colors.error : colors.onSurface;
    return ListTile(
      enabled: enabled,
      shape: const RoundedRectangleBorder(),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: NekoSpace.lg,
        vertical: 2,
      ),
      leading: icon == null
          ? null
          : Icon(icon, color: destructive ? colors.error : null),
      title: Text(title, style: text.bodyLarge?.copyWith(color: foreground)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      onTap: onTap,
      trailing:
          trailing ??
          (value == null && onTap == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (value != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          value!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (onTap != null) ...[
                      const SizedBox(width: NekoSpace.xs),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ],
                )),
    );
  }
}

class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.subtitle,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    shape: const RoundedRectangleBorder(),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: NekoSpace.lg,
      vertical: 2,
    ),
    secondary: icon == null ? null : Icon(icon),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    value: value,
    onChanged: onChanged,
  );
}

/// A settings row whose body is a custom control, such as a slider or a set
/// of chips, laid out under the title.
class SettingsControlTile extends StatelessWidget {
  const SettingsControlTile({
    super.key,
    required this.title,
    required this.child,
    this.value,
    this.subtitle,
  });

  final String title;
  final String? value;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NekoSpace.lg,
        NekoSpace.md,
        NekoSpace.lg,
        NekoSpace.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: text.bodyLarge)),
              if (value != null)
                Text(
                  value!,
                  style: text.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: text.bodySmall),
          ],
          const SizedBox(height: NekoSpace.sm),
          child,
        ],
      ),
    );
  }
}

/// An inline status message: informational, success or error.
class InlineNotice extends StatelessWidget {
  const InlineNotice(
    this.message, {
    super.key,
    this.error = false,
    this.action,
  });
  final String message;
  final bool error;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NekoSpace.lg,
        vertical: NekoSpace.md,
      ),
      decoration: BoxDecoration(
        color: error ? colors.errorContainer : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(NekoRadius.card),
      ),
      child: Row(
        children: [
          Icon(
            error ? Icons.error_outline : Icons.info_outline,
            size: 20,
            color: error ? colors.onErrorContainer : colors.onSurfaceVariant,
          ),
          const SizedBox(width: NekoSpace.md),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: error ? colors.onErrorContainer : colors.onSurface,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
