import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/map_region.dart';
import '../services/map_tile_cache_service.dart';
import '../widgets/adaptive_app_bar_title.dart';

/// Result of picking an area to pre-download.
class PickedRegion {
  final String name;
  final LatLngBounds bounds;
  final int minZoom;
  final int maxZoom;

  const PickedRegion({
    required this.name,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
  });
}

/// Choose an area of the basemap to download for offline use.
///
/// The area defaults to whatever the map is showing; dragging on the map draws
/// an explicit box instead. A detail slider sets the maximum zoom, which is the
/// dominant term in both tile count and size — each extra level roughly
/// quadruples the work, so the live estimate is the main guard against
/// starting a download that never finishes.
class MapRegionPickerScreen extends StatefulWidget {
  /// Where to open the map — normally the caller's current view.
  final LatLng initialCenter;
  final double initialZoom;

  const MapRegionPickerScreen({
    super.key,
    required this.initialCenter,
    required this.initialZoom,
  });

  @override
  State<MapRegionPickerScreen> createState() => _MapRegionPickerScreenState();
}

class _MapRegionPickerScreenState extends State<MapRegionPickerScreen> {
  static const int _minZoom = 0;
  static const double _pickerMinZoom = 2;
  static const double _pickerMaxZoom = 18;

  final MapController _mapController = MapController();
  final TextEditingController _nameController = TextEditingController();

  /// Explicit box drawn by dragging; null means "use the visible map".
  LatLng? _dragStart;
  LatLngBounds? _drawnBounds;
  bool _drawMode = false;

  int _maxZoom = 14;
  double _avgTileBytes = 12 * 1024;

  /// Upper bound of the detail slider — the archive's deepest zoom, so the
  /// estimate never counts tiles that cannot be fetched.
  int _zoomCeiling = 16;

  @override
  void initState() {
    super.initState();
    _nameController.text = 'Region';
    final cache = context.read<MapTileCacheService>();
    // Size estimates use this archive's own average tile size when the store
    // has enough samples to be meaningful.
    cache.averageTileBytes().then((v) {
      if (mounted) setState(() => _avgTileBytes = v);
    });
    cache.maxAvailableZoom().then((z) {
      if (!mounted) return;
      setState(() {
        _zoomCeiling = z;
        if (_maxZoom > z) _maxZoom = z;
      });
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// The area that would be downloaded: the drawn box, else the visible map.
  LatLngBounds? get _targetBounds {
    if (_drawnBounds != null) return _drawnBounds;
    try {
      return _mapController.camera.visibleBounds;
    } catch (_) {
      return null; // camera not ready on first frame
    }
  }

  int get _estimatedTiles {
    final b = _targetBounds;
    if (b == null) return 0;
    return MapRegion.estimateTiles(b, _minZoom, _maxZoom);
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

  void _handleDragStart(Offset localPosition) {
    final point = _mapController.camera.screenOffsetToLatLng(localPosition);
    setState(() {
      _dragStart = point;
      _drawnBounds = LatLngBounds(point, point);
    });
  }

  void _handleDragUpdate(Offset localPosition) {
    final start = _dragStart;
    if (start == null) return;
    final point = _mapController.camera.screenOffsetToLatLng(localPosition);
    setState(() => _drawnBounds = LatLngBounds(start, point));
  }

  bool get _drawnBoxIsUsable {
    final b = _drawnBounds;
    if (b == null) return false;
    // A tap (or a stray micro-drag) is not a region.
    return (b.north - b.south).abs() > 1e-4 && (b.east - b.west).abs() > 1e-4;
  }

  void _submit() {
    final bounds = _targetBounds;
    if (bounds == null) return;
    final name = _nameController.text.trim();
    Navigator.pop(
      context,
      PickedRegion(
        name: name.isEmpty ? 'Region' : name,
        bounds: bounds,
        minZoom: _minZoom,
        maxZoom: _maxZoom,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tiles = _estimatedTiles;
    final estBytes = tiles * _avgTileBytes;
    final drawn = _drawnBounds;

    return Scaffold(
      appBar: AppBar(
        title: const AdaptiveAppBarTitle('Download Region'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: _drawMode ? 'Done drawing' : 'Draw a box',
            icon: Icon(_drawMode ? Icons.pan_tool_alt : Icons.crop_free),
            onPressed: () => setState(() => _drawMode = !_drawMode),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: widget.initialCenter,
                    initialZoom: widget.initialZoom,
                    minZoom: _pickerMinZoom,
                    maxZoom: _pickerMaxZoom,
                    interactionOptions: InteractionOptions(
                      // Panning would fight the drag gesture while drawing.
                      flags: _drawMode
                          ? InteractiveFlag.none
                          : ~InteractiveFlag.rotate,
                    ),
                    onPositionChanged: (_, _) {
                      // Estimate tracks the viewport when no box is drawn.
                      if (_drawnBounds == null && mounted) setState(() {});
                    },
                  ),
                  children: [
                    context.read<MapTileCacheService>().buildTileLayer(context),
                    if (drawn != null)
                      _BoundsOverlay(bounds: drawn, color: scheme.primary),
                  ],
                ),
                if (_drawMode)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) => _handleDragStart(d.localPosition),
                      onPanUpdate: (d) => _handleDragUpdate(d.localPosition),
                      onPanEnd: (_) {
                        if (!_drawnBoxIsUsable) {
                          setState(() => _drawnBounds = null);
                        }
                        setState(() => _drawMode = false);
                      },
                    ),
                  ),
                if (_drawMode)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: _Banner(
                      text: 'Drag to draw the area to download',
                      color: scheme.primaryContainer,
                      onColor: scheme.onPrimaryContainer,
                    ),
                  ),
              ],
            ),
          ),
          _buildControls(context, tiles, estBytes),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context, int tiles, double estBytes) {
    final scheme = Theme.of(context).colorScheme;
    // Rough guard rails: past this the download stops being a quick errand.
    final heavy = tiles > 150000;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (_drawnBounds != null)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _drawnBounds = null;
                      _dragStart = null;
                    }),
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Use view'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Detail', style: Theme.of(context).textTheme.bodyMedium),
                Expanded(
                  child: Slider(
                    value: _maxZoom.clamp(8, _zoomCeiling).toDouble(),
                    min: 8,
                    max: _zoomCeiling.toDouble(),
                    divisions: (_zoomCeiling - 8).clamp(1, 16),
                    label: 'z$_maxZoom',
                    onChanged: (v) => setState(() => _maxZoom = v.round()),
                  ),
                ),
                Text(
                  'z$_maxZoom',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            Row(
              children: [
                Icon(
                  heavy ? Icons.warning_amber : Icons.info_outline,
                  size: 16,
                  color: heavy ? scheme.error : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${_formatCount(tiles)} tiles · ~${_formatBytes(estBytes)}'
                    '${heavy ? ' — this will take a while' : ''}',
                    style: TextStyle(
                      color: heavy ? scheme.error : scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: tiles == 0 ? null : _submit,
                icon: const Icon(Icons.download),
                label: const Text('Download'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCount(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '${(n / 1000000).toStringAsFixed(2)}M';
  }
}

/// Translucent rectangle showing the area that will be downloaded.
class _BoundsOverlay extends StatelessWidget {
  final LatLngBounds bounds;
  final Color color;

  const _BoundsOverlay({required this.bounds, required this.color});

  @override
  Widget build(BuildContext context) {
    return PolygonLayer(
      polygons: [
        Polygon(
          points: [
            LatLng(bounds.north, bounds.west),
            LatLng(bounds.north, bounds.east),
            LatLng(bounds.south, bounds.east),
            LatLng(bounds.south, bounds.west),
          ],
          color: color.withValues(alpha: 0.18),
          borderColor: color,
          borderStrokeWidth: 2,
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final Color color;
  final Color onColor;

  const _Banner({
    required this.text,
    required this.color,
    required this.onColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: onColor, fontSize: 13),
      ),
    );
  }
}
