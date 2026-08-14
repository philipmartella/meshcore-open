import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/map_region.dart';
import '../services/app_settings_service.dart';
import '../services/map_tile_cache_service.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../helpers/snack_bar_builder.dart';
import 'map_region_picker_screen.dart';

/// Offline basemap management.
///
/// The map is always served from a local store, so this screen is about what
/// that store holds: how much has accumulated from browsing, which areas were
/// pre-downloaded, and whether to stay off the network entirely.
class MapCacheScreen extends StatefulWidget {
  /// Where the region picker should open — normally the map's current view.
  final LatLng? initialCenter;
  final double initialZoom;

  const MapCacheScreen({super.key, this.initialCenter, this.initialZoom = 11});

  @override
  State<MapCacheScreen> createState() => _MapCacheScreenState();
}

class _MapCacheScreenState extends State<MapCacheScreen> {
  late Future<_StoreSummary> _summary;

  @override
  void initState() {
    super.initState();
    _summary = _loadSummary();
  }

  Future<_StoreSummary> _loadSummary() async {
    final cache = context.read<MapTileCacheService>();
    return _StoreSummary(
      tiles: await cache.storedTileCount(),
      bytes: await cache.storedBytes(),
      regions: await cache.regions(),
      archiveBytes: await cache.offlineArchiveBytes(),
    );
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _summary = _loadSummary());
  }

  void _snack(String message, {bool error = false}) {
    showDismissibleSnackBar(
      context,
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    );
  }

  String _formatBytes(num bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    double v = bytes.toDouble();
    int u = 0;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    return '${v.toStringAsFixed(v >= 100 || u == 0 ? 0 : 1)} ${units[u]}';
  }

  String _formatCount(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '${(n / 1000000).toStringAsFixed(2)}M';
  }

  Future<void> _pickAndDownloadRegion() async {
    final cache = context.read<MapTileCacheService>();
    final picked = await Navigator.push<PickedRegion>(
      context,
      MaterialPageRoute(
        builder: (_) => MapRegionPickerScreen(
          initialCenter: widget.initialCenter ?? const LatLng(0, 0),
          initialZoom: widget.initialZoom,
        ),
      ),
    );
    if (picked == null || !mounted) return;

    try {
      await cache.downloadRegion(
        name: picked.name,
        bounds: picked.bounds,
        minZoom: picked.minZoom,
        maxZoom: picked.maxZoom,
      );
      if (mounted) _snack('“${picked.name}” downloaded');
    } catch (e) {
      if (mounted) _snack('Download failed: $e', error: true);
    }
    _refresh();
  }

  Future<void> _resumeRegion(MapRegion region) async {
    try {
      await context.read<MapTileCacheService>().resumeRegion(region);
      if (mounted) _snack('“${region.name}” finished');
    } catch (e) {
      if (mounted) _snack('Resume failed: $e', error: true);
    }
    _refresh();
  }

  Future<void> _deleteRegion(MapRegion region) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete “${region.name}”?'),
        content: const Text(
          'Removes the downloaded tiles for this area. Areas covered by '
          'another download are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.common_delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = region.id;
    if (id == null) return;
    await context.read<MapTileCacheService>().deleteRegion(id);
    if (mounted) _snack('“${region.name}” deleted');
    _refresh();
  }

  Future<void> _clearStore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear offline map data?'),
        content: const Text(
          'Deletes every stored tile and downloaded area. The map will refill '
          'from the server as you browse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.common_clear),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<MapTileCacheService>().clearStore();
    if (mounted) _snack('Offline map data cleared');
    _refresh();
  }

  Future<void> _downloadWholeArchive() async {
    final cache = context.read<MapTileCacheService>();
    try {
      await cache.downloadOfflineArchive();
      if (mounted) _snack('Full archive downloaded');
    } catch (e) {
      if (mounted) _snack('Download failed: $e', error: true);
    }
    _refresh();
  }

  Future<void> _deleteWholeArchive() async {
    await context.read<MapTileCacheService>().deleteOfflineArchive();
    if (mounted) _snack('Full archive deleted');
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<MapTileCacheService>();
    final settings = context.watch<AppSettingsService>().settings;

    return Scaffold(
      appBar: AppBar(
        title: const AdaptiveAppBarTitle('Offline Maps'),
        centerTitle: true,
      ),
      body: FutureBuilder<_StoreSummary>(
        future: _summary,
        builder: (context, snap) {
          final s = snap.data;
          return ListView(
            children: [
              if (cache.isDownloadingRegion) _buildActiveDownload(cache),

              _SectionLabel('Stored map data'),
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: Text(
                  s == null
                      ? '…'
                      : '${_formatCount(s.tiles)} tiles · '
                            '${_formatBytes(s.bytes)}',
                ),
                subtitle: const Text(
                  'Fills automatically as you browse the map',
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.cloud_off_outlined),
                title: const Text('Offline only'),
                subtitle: const Text(
                  'Never fetch missing tiles over the network',
                ),
                value: settings.mapOfflineOnly,
                onChanged: (v) =>
                    context.read<AppSettingsService>().setMapOfflineOnly(v),
              ),
              const Divider(height: 1),

              _SectionLabel('Downloaded areas'),
              if (s != null && s.regions.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'No areas downloaded yet. Download one to guarantee '
                    'coverage where you have no signal.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              if (s != null)
                ...s.regions.map(
                  (r) => ListTile(
                    leading: Icon(
                      r.complete ? Icons.map_outlined : Icons.pending_outlined,
                    ),
                    title: Text(r.name),
                    subtitle: Text(
                      '${_formatCount(r.tileCount)} tiles · '
                      '${_formatBytes(r.bytes)} · z${r.minZoom}–${r.maxZoom}'
                      '${r.complete ? '' : ' · incomplete'}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // An interrupted download continues from where it
                        // stopped — stored tiles are skipped, not refetched.
                        if (!r.complete)
                          IconButton(
                            icon: const Icon(Icons.play_arrow),
                            tooltip: 'Resume download',
                            onPressed: cache.isDownloadingRegion
                                ? null
                                : () => _resumeRegion(r),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete',
                          onPressed: () => _deleteRegion(r),
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: cache.isDownloadingRegion
                        ? null
                        : _pickAndDownloadRegion,
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Download an area'),
                  ),
                ),
              ),
              const Divider(height: 1),

              _SectionLabel('Entire coverage area'),
              _buildWholeArchiveTile(cache, s),
              const Divider(height: 1),

              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('Clear offline map data'),
                subtitle: const Text('Removes all stored tiles and areas'),
                trailing: TextButton(
                  onPressed: _clearStore,
                  child: Text(context.l10n.common_clear),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActiveDownload(MapTileCacheService cache) {
    final p = cache.regionProgress;
    final name = cache.downloadingRegionName ?? 'Region';
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Downloading “$name”',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: cache.cancelRegionDownload,
                  child: Text(context.l10n.common_cancel),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: p?.fraction),
            const SizedBox(height: 6),
            Text(
              p == null
                  ? 'Starting…'
                  : '${_formatCount(p.completed)} / ${_formatCount(p.total)} '
                        'tiles · ${_formatBytes(p.bytes)}'
                        '${p.failed > 0 ? ' · ${p.failed} failed' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWholeArchiveTile(
    MapTileCacheService cache,
    _StoreSummary? summary,
  ) {
    final downloading = cache.isDownloadingOffline;
    final progress = cache.offlineDownloadProgress;
    final bytes = summary?.archiveBytes ?? 0;
    final exists = bytes > 0;

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.public),
          title: const Text('Full archive'),
          subtitle: Text(
            downloading
                ? 'Downloading… '
                      '${progress == null ? '' : '${(progress * 100).toStringAsFixed(0)}%'}'
                : exists
                ? 'Downloaded — ${_formatBytes(bytes)}'
                : 'Every area at once — a large download',
          ),
          trailing: downloading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : exists
              ? IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: _deleteWholeArchive,
                )
              : TextButton(
                  onPressed: _downloadWholeArchive,
                  child: const Text('Download'),
                ),
        ),
        if (downloading && progress != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(value: progress),
          ),
      ],
    );
  }
}

class _StoreSummary {
  final int tiles;
  final int bytes;
  final List<MapRegion> regions;
  final int archiveBytes;

  const _StoreSummary({
    required this.tiles,
    required this.bytes,
    required this.regions,
    required this.archiveBytes,
  });
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
