import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/app_settings_service.dart';
import '../services/map_tile_cache_service.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../helpers/snack_bar_builder.dart';

/// Offline basemap management for the vector (PMTiles) map.
///
/// Two things live here:
///   - the runtime tile cache (browsed tiles kept on disk) — clearable
///   - a full-archive offline download — copies the entire .pmtiles locally so
///     the whole region works with no network; a toggle switches the basemap
///     between the downloaded copy and the streamed URL.
class MapCacheScreen extends StatefulWidget {
  const MapCacheScreen({super.key});

  @override
  State<MapCacheScreen> createState() => _MapCacheScreenState();
}

class _MapCacheScreenState extends State<MapCacheScreen> {
  void _snack(String message, {bool error = false}) {
    showDismissibleSnackBar(
      context,
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    );
  }

  String _formatBytes(int bytes) {
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

  Future<void> _download(MapTileCacheService cache) async {
    try {
      await cache.downloadOfflineArchive();
      if (!mounted) return;
      _snack('Offline basemap downloaded');
    } catch (e) {
      if (!mounted) return;
      _snack('Download failed: $e', error: true);
    }
  }

  Future<void> _delete(MapTileCacheService cache) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete offline basemap?'),
        content: const Text(
          'Removes the downloaded archive. The map will stream from the '
          'server again.',
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
    if (confirmed != true) return;
    await cache.deleteOfflineArchive();
    // If we were using the offline copy, fall back to streaming.
    if (mounted) {
      await context.read<AppSettingsService>().setMapVectorUseOffline(false);
    }
    if (mounted) _snack('Offline basemap deleted');
  }

  Future<void> _clearRuntimeCache(MapTileCacheService cache) async {
    await cache.clearCache();
    if (mounted) _snack('Tile cache cleared');
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<MapTileCacheService>();
    final settings = context.watch<AppSettingsService>().settings;

    return Scaffold(
      appBar: AppBar(
        title: const AdaptiveAppBarTitle('Offline Basemap'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.link_outlined),
            title: const Text('Tiles source'),
            subtitle: Text(
              settings.mapVectorTilesUrl,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),

          // Offline full-archive download.
          FutureBuilder<int>(
            future: cache.offlineArchiveBytes(),
            builder: (context, snap) {
              final bytes = snap.data ?? 0;
              final exists = bytes > 0;
              final downloading = cache.isDownloadingOffline;
              final progress = cache.offlineDownloadProgress;
              return Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.download_for_offline_outlined),
                    title: const Text('Offline archive'),
                    subtitle: Text(
                      downloading
                          ? 'Downloading… '
                                '${progress == null ? '' : '${(progress * 100).toStringAsFixed(0)}%'}'
                          : exists
                          ? 'Downloaded — ${_formatBytes(bytes)}'
                          : 'Not downloaded',
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
                            onPressed: () => _delete(cache),
                          )
                        : null,
                  ),
                  if (downloading && progress != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: LinearProgressIndicator(value: progress),
                    ),
                  if (!downloading)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(Icons.download),
                              label: Text(
                                exists ? 'Re-download' : 'Download for offline',
                              ),
                              onPressed: () => _download(cache),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SwitchListTile(
                    secondary: const Icon(Icons.cloud_off_outlined),
                    title: const Text('Use offline copy'),
                    subtitle: Text(
                      exists
                          ? 'Read the map from the downloaded archive'
                          : 'Download the archive first',
                    ),
                    value: settings.mapVectorUseOffline && exists,
                    onChanged: exists
                        ? (v) => context
                              .read<AppSettingsService>()
                              .setMapVectorUseOffline(v)
                        : null,
                  ),
                ],
              );
            },
          ),
          const Divider(height: 1),

          // Runtime browse cache.
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Clear tile cache'),
            subtitle: const Text(
              'Removes cached tiles from areas you have browsed',
            ),
            trailing: TextButton(
              onPressed: () => _clearRuntimeCache(cache),
              child: Text(context.l10n.common_clear),
            ),
          ),
        ],
      ),
    );
  }
}
