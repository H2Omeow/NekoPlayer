import 'package:flutter/material.dart';

import '../neko_theme.dart';

/// Horizontal padding for page content; narrow windows get less.
double pageGutter(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 720 ? NekoSpace.lg : NekoSpace.xxl;

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.bottom = NekoSpace.xl,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(top: NekoSpace.xl, bottom: bottom),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: NekoSpace.xl,
        runSpacing: NekoSpace.md,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: text.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: NekoSpace.xs),
                Text(
                  subtitle!,
                  style: text.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          if (actions.isNotEmpty)
            Wrap(
              spacing: NekoSpace.sm,
              runSpacing: NekoSpace.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: NekoSpace.xxl, bottom: NekoSpace.md),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?action,
      ],
    ),
  );
}

/// Root layout for a page shown inside the content panel: a padded,
/// scrollable column with an optional maximum width.
class PanelPage extends StatelessWidget {
  const PanelPage({
    super.key,
    required this.children,
    this.maxWidth,
    this.controller,
  });

  final List<Widget> children;
  final double? maxWidth;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final gutter = pageGutter(context);
    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    if (maxWidth != null) {
      content = Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth!),
          child: content,
        ),
      );
    }
    return SingleChildScrollView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, NekoSpace.xxl),
      child: content,
    );
  }
}

/// A detail page pushed inside the content panel, with a back button and
/// a constrained single column. Used by settings sub-pages and the like.
class DetailPage extends StatelessWidget {
  const DetailPage({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.maxWidth = 760,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: [
        ...actions,
        const SizedBox(width: NekoSpace.sm),
      ],
    ),
    body: PanelPage(
      maxWidth: maxWidth,
      children: [
        const SizedBox(height: NekoSpace.sm),
        ...children,
      ],
    ),
  );
}
