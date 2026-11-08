import '../../i18n/tr.dart';
import 'package:flutter/material.dart';

import '../neko_theme.dart';
import 'artwork.dart';

/// One entry of a song's context menu.
class SongAction {
  const SongAction(
    this.label,
    this.icon,
    this.onSelected, {
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final bool destructive;
  final bool enabled;
}

/// The single song row used by every list in the app: library, playlists,
/// search results, account libraries and the queue.
class SongRow extends StatefulWidget {
  const SongRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.artwork,
    this.artworkSeed,
    this.index,
    this.album,
    this.playing = false,
    this.favorite,
    this.onFavorite,
    this.onTap,
    this.actions = const [],
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String? artwork;
  final String? artworkSeed;
  final int? index;
  final String? album;
  final bool playing;
  final bool? favorite;
  final VoidCallback? onFavorite;
  final VoidCallback? onTap;
  final List<SongAction> actions;
  final Widget? trailing;

  @override
  State<SongRow> createState() => _SongRowState();
}

class _SongRowState extends State<SongRow> {
  bool hovered = false;

  Future<void> showMenuAt(Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<SongAction>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [for (final action in widget.actions) _menuItem(context, action)],
    );
    selected?.onSelected();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final palette = NekoPalette.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final showControls = hovered || widget.playing;
    final leading = widget.index == null
        ? null
        : SizedBox(
            width: 28,
            child: Center(
              child: widget.playing
                  ? Icon(
                      Icons.graphic_eq_rounded,
                      size: 18,
                      color: palette.accent,
                    )
                  : hovered && widget.onTap != null
                  ? Icon(
                      Icons.play_arrow_rounded,
                      size: 20,
                      color: colors.onSurface,
                    )
                  : Text(
                      '${widget.index! + 1}',
                      style: text.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
            ),
          );
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onSecondaryTapUp: widget.actions.isEmpty
            ? null
            : (details) => showMenuAt(details.globalPosition),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(NekoRadius.control),
            hoverColor: palette.hover,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NekoSpace.sm,
                vertical: 6,
              ),
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading,
                    const SizedBox(width: NekoSpace.sm),
                  ],
                  Artwork(
                    size: 44,
                    url: widget.artwork,
                    label: widget.artworkSeed ?? widget.title,
                  ),
                  const SizedBox(width: NekoSpace.md),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: widget.playing ? palette.accent : null,
                          ),
                        ),
                        Text(
                          widget.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (wide && (widget.album?.isNotEmpty ?? false)) ...[
                    const SizedBox(width: NekoSpace.lg),
                    Expanded(
                      flex: 3,
                      child: Text(
                        widget.album!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  ?widget.trailing,
                  if (widget.favorite != null && widget.onFavorite != null)
                    Opacity(
                      opacity: widget.favorite! || showControls ? 1 : 0,
                      child: IconButton(
                        tooltip: widget.favorite! ? tr('取消收藏') : tr('收藏'),
                        onPressed: widget.onFavorite,
                        iconSize: 20,
                        icon: Icon(
                          widget.favorite!
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: widget.favorite! ? palette.accent : null,
                        ),
                      ),
                    ),
                  if (widget.actions.isNotEmpty)
                    Opacity(
                      opacity: showControls ? 1 : 0.55,
                      child: PopupMenuButton<SongAction>(
                        tooltip: tr('歌曲操作'),
                        icon: const Icon(Icons.more_horiz_rounded, size: 20),
                        onSelected: (action) => action.onSelected(),
                        itemBuilder: (context) => [
                          for (final action in widget.actions)
                            _menuItem(context, action),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

PopupMenuItem<SongAction> _menuItem(BuildContext context, SongAction action) {
  final color = action.destructive ? Theme.of(context).colorScheme.error : null;
  return PopupMenuItem(
    value: action,
    enabled: action.enabled,
    height: 40,
    child: Row(
      children: [
        Icon(action.icon, size: 18, color: color),
        const SizedBox(width: NekoSpace.md),
        Text(action.label, style: TextStyle(color: color)),
      ],
    ),
  );
}
