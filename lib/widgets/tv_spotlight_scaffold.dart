import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';
import '../media/catalog_item_ref.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_server_client.dart';
import '../models/catalog/catalog_item.dart';
import '../navigation/main_screen_scope.dart';
import '../services/settings_service.dart';
import '../utils/debouncer.dart';
import '../utils/layout_constants.dart';
import '../utils/formatters.dart';
import 'tv_browse_rail.dart';
import 'tv_spotlight_background.dart';

class TvSpotlightController extends ValueNotifier<MediaItem?> {
  TvSpotlightController({Duration settleDelay = const Duration(milliseconds: 150)})
    : _settleDelay = settleDelay,
      _debouncer = Debouncer(settleDelay),
      super(null);

  final Duration _settleDelay;
  final Debouncer _debouncer;

  void select(MediaItem item) {
    void apply() {
      if (value?.globalKey == item.globalKey) return;
      value = item;
    }

    if (_settleDelay == Duration.zero) {
      apply();
    } else {
      _debouncer.run(apply);
    }
  }

  MediaItem? resolve(Iterable<MediaHub> hubs) {
    MediaItem? fallback;
    final current = value;
    for (final hub in hubs) {
      if (hub.items.isEmpty) continue;
      fallback ??= hub.items.first;
      if (current == null) continue;
      for (final item in hub.items) {
        if (item.globalKey == current.globalKey) return item;
      }
    }
    return fallback;
  }

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }
}

typedef TvSpotlightClientResolver = MediaServerClient? Function(MediaItem? item);

/// Shared full-screen TV backdrop and foreground stack used by hub rails.
class TvSpotlightScaffold extends StatelessWidget {
  const TvSpotlightScaffold({
    super.key,
    required this.hubs,
    required this.spotlightListenable,
    required this.resolveSpotlight,
    required this.resolveClient,
    required this.foreground,
    this.hideSpoilers,
    this.showContinueWatchingServerSource = false,
  });

  final List<MediaHub> hubs;
  final ValueListenable<MediaItem?> spotlightListenable;
  final MediaItem? Function() resolveSpotlight;
  final TvSpotlightClientResolver resolveClient;
  final Widget foreground;
  final bool? hideSpoilers;
  /// Show the source server/library for items in the combined Continue Watching rail.
  final bool showContinueWatchingServerSource;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final settings = SettingsService.instance;
    final scale = TvLayoutConstants.scaleForSize(size);
    final railSize = MainScreenFocusScope.foregroundSizeOf(context);
    final fullBleedWidth = MainScreenFocusScope.fullBleedWidthOf(context);
    final continueWatchingKeys = <String>{
      if (showContinueWatchingServerSource)
        for (final hub in hubs)
          if (hub.id == 'continue_watching')
            for (final item in hub.items) item.globalKey,
    };
    final railHeight = hubs.isEmpty
        ? 0.0
        : TvBrowseRailLayout.estimateHeight(
            size: railSize,
            hubs: hubs,
            density: settings.read(SettingsService.libraryDensity),
            episodePosterMode: settings.read(SettingsService.episodePosterMode),
            fullCardLayout: settings.read(SettingsService.tvFullCardLayout),
            gridSpacing: settings.read(SettingsService.gridSpacing),
            tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
            widePosterScale: TvBrowseRailLayout.compactEpisodeThumbnailScale,
          );
    final spotlightTop = (size.height * 0.075).clamp(64.0 * scale, 120.0 * scale).toDouble();
    final minimumSpotlightBottom = railHeight + (8 * scale);
    final baseSpotlightBottom = (size.height * 0.48).clamp(160.0, 820.0).toDouble();
    final desiredSpotlightBottom = minimumSpotlightBottom > baseSpotlightBottom
        ? minimumSpotlightBottom
        : baseSpotlightBottom;
    final maxSpotlightBottom = (size.height - spotlightTop - (96 * scale)).clamp(0.0, double.infinity).toDouble();
    final spotlightBottom = desiredSpotlightBottom > maxSpotlightBottom ? maxSpotlightBottom : desiredSpotlightBottom;
    final spotlightLeft = (24 * scale).clamp(18.0, 40.0).toDouble();

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Builder(
              builder: (context) {
                final foregroundLeft = MainScreenFocusScope.foregroundLeftOf(context);
                return SideNavigationBleedBuilder(
                  targetBleed: foregroundLeft,
                  child: ValueListenableBuilder<MediaItem?>(
                    valueListenable: spotlightListenable,
                    builder: (context, _, _) {
                      final spotlight = resolveSpotlight();
                      return _CatalogSpotlightBackground(
                        item: spotlight,
                        client: resolveClient(spotlight),
                        showSourceLabel: spotlight != null && continueWatchingKeys.contains(spotlight.globalKey),
                        hideSpoilers: hideSpoilers ?? settings.read(SettingsService.hideSpoilers),
                        contentTop: spotlightTop,
                        contentBottom: spotlightBottom,
                        contentLeft: spotlightLeft + foregroundLeft,
                        targetWidthPx: (size.width * MediaQuery.devicePixelRatioOf(context)).ceil(),
                      );
                    },
                  ),
                  builder: (context, animatedBleed, child) =>
                      Positioned(top: 0, bottom: 0, left: -animatedBleed, width: fullBleedWidth, child: child!),
                );
              },
            ),
            foreground,
          ],
        ),
      ),
    );
  }
}

class _CatalogSpotlightBackground extends StatefulWidget {
  const _CatalogSpotlightBackground({
    required this.item,
    required this.client,
    required this.showSourceLabel,
    required this.hideSpoilers,
    required this.contentTop,
    required this.contentBottom,
    required this.contentLeft,
    required this.targetWidthPx,
  });

  final MediaItem? item;
  final MediaServerClient? client;
  final bool showSourceLabel;
  final bool hideSpoilers;
  final double contentTop;
  final double contentBottom;
  final double contentLeft;
  final int targetWidthPx;

  @override
  State<_CatalogSpotlightBackground> createState() => _CatalogSpotlightBackgroundState();
}

class _CatalogSpotlightBackgroundState extends State<_CatalogSpotlightBackground> {
  CatalogItem? _catalogItem;
  MediaItem? _renderItem;
  Color? _accentColor;

  // A Jellyfin/Emby Continue Watching row carries no library identity. Resolve
  // it only for the focused item, not for the entire row, and reuse results
  // while navigating back and forth with the remote.
  final Map<String, String> _libraryTitleCache = {};
  final Set<String> _pendingLibraryLookups = {};

  @override
  void initState() {
    super.initState();
    _rehydrateCatalogItem();
    _maybeResolveSourceLibrary();
  }

  @override
  void didUpdateWidget(_CatalogSpotlightBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.item, oldWidget.item)) {
      _rehydrateCatalogItem();
    } else if (widget.targetWidthPx != oldWidget.targetWidthPx) {
      _projectArtwork();
    }
    if (!identical(widget.item, oldWidget.item) ||
        !identical(widget.client, oldWidget.client) ||
        widget.showSourceLabel != oldWidget.showSourceLabel) {
      _maybeResolveSourceLibrary();
    }
  }

  void _maybeResolveSourceLibrary() {
    final item = widget.item;
    final client = widget.client;
    if (!widget.showSourceLabel || item == null || client == null) return;
    // Plex rows already have their library metadata; only MediaBrowser rows
    // require an additional ancestry lookup.
    if (item.backend != MediaBackend.jellyfin && item.backend != MediaBackend.emby) return;
    if (item.libraryTitle?.trim().isNotEmpty ?? false) return;

    final key = item.globalKey;
    if (_libraryTitleCache.containsKey(key) || !_pendingLibraryLookups.add(key)) return;
    unawaited(_loadSourceLibrary(item, client, key));
  }

  Future<void> _loadSourceLibrary(MediaItem item, MediaServerClient client, String key) async {
    String? title;
    try {
      // The Jellyfin/Emby client uses /Items/{id}/Ancestors to identify the
      // owning CollectionFolder. This is best-effort and never blocks playback.
      title = (await client.stampLibrary(item)).libraryTitle?.trim();
    } catch (_) {
      // Keep showing the server alone if the lookup is unavailable.
    }

    if (!mounted) return;
    _pendingLibraryLookups.remove(key);
    if (title == null || title.isEmpty) return;
    if (_libraryTitleCache.length >= 64) {
      _libraryTitleCache.remove(_libraryTitleCache.keys.first);
    }
    _libraryTitleCache[key] = title;
    if (widget.showSourceLabel && widget.item?.globalKey == key) setState(() {});
  }

  void _rehydrateCatalogItem() {
    _catalogItem = widget.item?.catalogItem;
    _projectArtwork();
  }

  void _projectArtwork() {
    final item = widget.item;
    final catalogItem = _catalogItem;
    if (item == null || catalogItem == null) {
      _renderItem = item;
      _accentColor = null;
      return;
    }

    final bannerUrl = catalogItem.bannerUrl;
    final backdrop = bannerUrl != null && bannerUrl.isNotEmpty
        ? bannerUrl
        : catalogItem.backdropFor(widget.targetWidthPx);
    final logoUrl = catalogItem.logoUrl;
    _renderItem = item.copyWith(
      artPath: backdrop ?? item.artPath,
      backdropPaths: backdrop == null ? item.backdropPaths : [backdrop],
      clearLogoPath: logoUrl != null && logoUrl.isNotEmpty ? logoUrl : null,
    );
    _accentColor = _parseAccentColor(catalogItem.accentColor);
  }

  Color? _parseAccentColor(String? value) {
    final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(value ?? '');
    final hex = match?.group(1);
    if (hex == null) return null;
    return Color(0xff000000 | int.parse(hex, radix: 16));
  }

  Widget? _buildNextEpisodeMetadata(BuildContext context) {
    final nextEpisode = _catalogItem?.nextEpisode;
    if (nextEpisode == null) return null;
    final duration = formatDurationTextual(nextEpisode.timeUntil(DateTime.now()).inMilliseconds);
    final episode = nextEpisode.episode;
    final label = episode == null
        ? t.explore.badge.nextAiringIn(duration: duration)
        : t.explore.badge.nextEpisodeIn(episode: episode, duration: duration);
    final scale = TvLayoutConstants.scaleOf(context);
    return Text(
      label,
      maxLines: 1,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 16 * scale,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
    );
  }

  String? get _sourceLabel {
    if (!widget.showSourceLabel) return null;
    final item = widget.item;
    if (item == null) return null;
    final namedOnItem = item.serverName?.trim();
    final namedOnClient = widget.client?.serverName?.trim();
    final serverName = namedOnItem != null && namedOnItem.isNotEmpty ? namedOnItem : namedOnClient;
    if (serverName == null || serverName.isEmpty) return null;
    final directLibrary = item.libraryTitle?.trim();
    final library = directLibrary != null && directLibrary.isNotEmpty
        ? directLibrary
        : _libraryTitleCache[item.globalKey];
    return library == null || library.isEmpty ? serverName : '$serverName • $library';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = _accentColor;
    final background = TvSpotlightBackground(
      item: _renderItem,
      client: widget.client,
      hideSpoilers: widget.hideSpoilers,
      sourceLabel: _sourceLabel,
      contentTop: widget.contentTop,
      contentBottom: widget.contentBottom,
      contentLeft: widget.contentLeft,
      compact: true,
      metadataTrailing: _buildNextEpisodeMetadata(context),
    );
    if (accentColor == null) return background;
    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: Color.alphaBlend(accentColor.withValues(alpha: 0.18), theme.scaffoldBackgroundColor),
      ),
      child: background,
    );
  }
}

/// Pins a toolbar to the top of the viewport across the full bleed width,
/// sliding with the sidebar so it stays put while the content box translates.
///
/// Excluded from default focus traversal so that initial/tab-switch focus
/// lands on content (hero/rails) rather than the toolbar; its buttons stay
/// reachable via explicit UP from the content. Reads the offset aspect from
/// its own element, so a sidebar flip rebuilds only this overlay.
class TvToolbarOverlay extends StatelessWidget {
  const TvToolbarOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fullBleedWidth = MainScreenFocusScope.fullBleedWidthOf(context);
    return SideNavigationBleedBuilder(
      targetBleed: MainScreenFocusScope.sideNavigationBleedOf(context),
      child: ExcludeFocusTraversal(child: child),
      builder: (context, animatedBleed, child) =>
          Positioned(top: 0, left: -animatedBleed, width: fullBleedWidth, child: child!),
    );
  }
}
