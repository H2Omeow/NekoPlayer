import 'package:flutter/material.dart';

import '../../player_controller.dart';
import '../neko_theme.dart';
import '../widgets/artwork.dart';
import 'destinations.dart';

/// Left navigation: top-level pages, library collections and the user's
/// playlists, with settings pinned at the bottom.
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.player,
    required this.selected,
    required this.onSelect,
    required this.onCreatePlaylist,
    required this.collapsed,
    this.showDownloads = false,
    this.showPlatform = false,
    this.accountLabel,
  });

  final PlayerController player;
  final Destination selected;
  final ValueChanged<Destination> onSelect;
  final VoidCallback onCreatePlaylist;
  final bool collapsed;
  final bool showDownloads;
  final bool showPlatform;
  final String? accountLabel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: player,
    builder: (context, _) {
      final text = Theme.of(context).textTheme;
      final colors = Theme.of(context).colorScheme;
      Widget item(
        Section section, {
        String? playlistId,
        String? label,
        String? artwork,
        String? trailing,
      }) {
        final destination = Destination(section, playlistId);
        return _SidebarItem(
          icon: section.icon,
          selectedIcon: section.selectedIcon,
          label: label ?? section.label,
          artwork: artwork,
          trailing: trailing,
          selected: selected == destination,
          collapsed: collapsed,
          onTap: () => onSelect(destination),
        );
      }

      Widget heading(String label, {Widget? action}) => collapsed
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: NekoSpace.sm),
              child: Divider(indent: 20, endIndent: 20),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                NekoSpace.lg,
                NekoSpace.lg,
                NekoSpace.xs,
                NekoSpace.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: text.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ?action,
                ],
              ),
            );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              collapsed ? 0 : NekoSpace.lg,
              NekoSpace.lg,
              NekoSpace.lg,
              NekoSpace.md,
            ),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                const _Logo(),
                if (!collapsed) ...[
                  const SizedBox(width: NekoSpace.md),
                  Text('NekoPlayer', style: text.titleMedium),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: NekoSpace.sm),
              children: [
                item(Section.home),
                item(Section.discover),
                heading('音乐库'),
                item(
                  Section.favorites,
                  trailing: collapsed ? null : '${player.favorites.length}',
                ),
                item(Section.recent),
                item(
                  Section.all,
                  trailing: collapsed ? null : '${player.tracks.length}',
                ),
                if (showDownloads) item(Section.downloads),
                if (showPlatform) item(Section.platform),
                heading(
                  '歌单',
                  action: IconButton(
                    tooltip: '新建歌单',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    onPressed: onCreatePlaylist,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ),
                if (collapsed)
                  _SidebarItem(
                    icon: Icons.add_rounded,
                    selectedIcon: Icons.add_rounded,
                    label: '新建歌单',
                    selected: false,
                    collapsed: true,
                    onTap: onCreatePlaylist,
                  ),
                for (final playlist in player.playlists)
                  item(
                    Section.playlist,
                    playlistId: playlist.id,
                    label: playlist.name,
                    artwork: player
                        .playlistTracks(playlist)
                        .map((track) => track.online?.artwork ?? '')
                        .where((url) => url.isNotEmpty)
                        .firstOrNull,
                  ),
                if (player.playlists.isEmpty && !collapsed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      NekoSpace.md,
                      NekoSpace.xs,
                      NekoSpace.md,
                      NekoSpace.md,
                    ),
                    child: Text('还没有歌单', style: text.bodySmall),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NekoSpace.sm,
              NekoSpace.xs,
              NekoSpace.sm,
              NekoSpace.md,
            ),
            child: _SidebarItem(
              icon: Section.settings.icon,
              selectedIcon: Section.settings.selectedIcon,
              label: Section.settings.label,
              trailing: collapsed ? null : accountLabel,
              selected: selected.section == Section.settings,
              collapsed: collapsed,
              onTap: () => onSelect(const Destination(Section.settings)),
            ),
          ),
        ],
      );
    },
  );
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final palette = NekoPalette.of(context);
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: palette.accent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Icon(
        Icons.graphic_eq_rounded,
        color: Colors.white,
        size: 20,
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.artwork,
    this.trailing,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;
  final String? artwork;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final foreground = selected ? colors.onSurface : colors.onSurfaceVariant;
    final leading = artwork != null
        ? Artwork(size: 24, url: artwork, label: label, radius: 4)
        : Icon(selected ? selectedIcon : icon, size: 22, color: foreground);
    final body = Material(
      color: selected
          ? colors.onSurface.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(NekoRadius.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(NekoRadius.control),
        onTap: onTap,
        child: SizedBox(
          height: 40,
          child: collapsed
              ? Center(child: leading)
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: NekoSpace.md),
                  child: Row(
                    children: [
                      leading,
                      const SizedBox(width: NekoSpace.md),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(
                            color: foreground,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (trailing != null)
                        Text(trailing!, style: text.labelSmall),
                    ],
                  ),
                ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: collapsed ? Tooltip(message: label, child: body) : body,
    );
  }
}
