import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import '../connector/meshcore_protocol.dart';

/// Data models for the Martellaville AMPM firmware fork's custom features:
/// the FlockYou surveillance-camera detector and the GPS track logger.
///
/// The wire layouts here are the authoritative Dart mirror of the packed
/// structs in the firmware (examples/companion_ampm/FlockYouScanner.cpp and
/// GpsTracker.h) and the parsers in meshcore-cli's ampm.py. All multi-byte
/// fields are little-endian with no struct padding (C `#pragma pack`), so the
/// sequential [BufferReader] reads line up 1:1 with the `struct` formats.

/// One surveillance-camera detection from the FlockYou scanner.
///
/// Wire layout: `<6sbBIH?ii>` == 23 bytes (DetectionRecord in
/// FlockYouScanner.h): mac[6], int8 rssi, uint8 channel, uint32 lastSeen,
/// uint16 count, uint8 hasGps, int32 lat_e6, int32 lon_e6.
class FlockYouDetection {
  /// Colon-separated lowercase MAC, e.g. `aa:bb:cc:dd:ee:ff`.
  final String mac;

  /// Last-seen signal strength, dBm (signed).
  final int rssi;

  /// Wi-Fi channel the beacon was heard on.
  final int channel;

  /// Device uptime (`millis()`) at the most recent sighting.
  final int lastSeenMs;

  /// Number of times this MAC has been seen.
  final int count;

  /// True when [lat]/[lon] carry a valid fix (the device had GPS at capture).
  final bool hasGps;

  final double? lat;
  final double? lon;

  const FlockYouDetection({
    required this.mac,
    required this.rssi,
    required this.channel,
    required this.lastSeenMs,
    required this.count,
    required this.hasGps,
    this.lat,
    this.lon,
  });

  /// Packed size of one detection on the wire.
  static const int wireSize = 23;

  /// Map location, or null when the detection carries no fix.
  LatLng? get location =>
      (hasGps && lat != null && lon != null) ? LatLng(lat!, lon!) : null;

  factory FlockYouDetection.fromReader(BufferReader r) {
    final mac = r.readBytes(6);
    final rssi = r.readInt8();
    // uint8_t in the firmware's DetectionRecord (meshcli reads it signed, which
    // is wrong for 5 GHz channels > 127 — the firmware is authoritative here).
    final channel = r.readUInt8();
    final lastSeenMs = r.readUInt32LE();
    final count = r.readUInt16LE();
    final hasGps = r.readUInt8() != 0;
    final latE6 = r.readInt32LE();
    final lonE6 = r.readInt32LE();
    return FlockYouDetection(
      mac: mac
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(':'),
      rssi: rssi,
      channel: channel,
      lastSeenMs: lastSeenMs,
      count: count,
      hasGps: hasGps,
      lat: hasGps ? latE6 / 1e6 : null,
      lon: hasGps ? lonE6 / 1e6 : null,
    );
  }
}

/// FlockYou scanner status (RESP_CODE_FLOCKYOU_STATUS payload, 6 bytes after
/// the response code: `<BHBBB>`).
class FlockYouStatus {
  final bool scanning;
  final int detectionCount;
  final int currentChannel;

  /// 0 == PreferBT, 1 == PreferWifi (CoexBias in FlockYouScanner.h).
  final int coexBias;
  final int dedupeActive;

  const FlockYouStatus({
    required this.scanning,
    required this.detectionCount,
    required this.currentChannel,
    required this.coexBias,
    required this.dedupeActive,
  });

  static FlockYouStatus? parse(Uint8List frame) {
    if (frame.length < 7 || frame[0] != respCodeFlockYouStatus) return null;
    final r = BufferReader(frame);
    r.skipBytes(1); // response code
    final scanning = r.readUInt8() != 0;
    final count = r.readUInt16LE();
    final channel = r.readUInt8();
    final bias = r.readUInt8();
    final dedupe = r.readUInt8();
    return FlockYouStatus(
      scanning: scanning,
      detectionCount: count,
      currentChannel: channel,
      coexBias: bias,
      dedupeActive: dedupe,
    );
  }
}

/// One GPS fix from the track logger.
///
/// Wire layout: `<IiiBHB>` == 16 bytes (GpsTracker::Fix).
class GpsFix {
  /// UTC epoch seconds.
  final int ts;
  final double lat;
  final double lon;

  /// Ground speed, km/h.
  final int kph;

  /// Heading, degrees 0-359.
  final int course;

  const GpsFix({
    required this.ts,
    required this.lat,
    required this.lon,
    required this.kph,
    required this.course,
  });

  static const int wireSize = 16;

  LatLng get location => LatLng(lat, lon);

  factory GpsFix.fromReader(BufferReader r) {
    final ts = r.readUInt32LE();
    final latE6 = r.readInt32LE();
    final lonE6 = r.readInt32LE();
    final kph = r.readUInt8();
    final course = r.readUInt16LE();
    r.skipBytes(1); // reserved
    return GpsFix(
      ts: ts,
      lat: latE6 / 1e6,
      lon: lonE6 / 1e6,
      kph: kph,
      course: course,
    );
  }
}

/// Index entry for one on-device track chunk.
///
/// Wire layout: `<IIIHH>` == 16 bytes (GpsTracker::ChunkIndex).
class GpsChunkIndex {
  final int chunkId;
  final int startTs;
  final int endTs;
  final int fixCount;

  const GpsChunkIndex({
    required this.chunkId,
    required this.startTs,
    required this.endTs,
    required this.fixCount,
  });

  static const int wireSize = 16;

  factory GpsChunkIndex.fromReader(BufferReader r) {
    final chunkId = r.readUInt32LE();
    final startTs = r.readUInt32LE();
    final endTs = r.readUInt32LE();
    final fixCount = r.readUInt16LE();
    r.skipBytes(2); // reserved
    return GpsChunkIndex(
      chunkId: chunkId,
      startTs: startTs,
      endTs: endTs,
      fixCount: fixCount,
    );
  }
}

/// Track-logger status plus one page of chunk indices (the LIST response).
///
/// Header is 22 bytes; see the CMD_GPS_TRACK_LIST handler in MyMesh.cpp:
///   [0]      response code
///   [1..2]   u16 total_chunks
///   [3..6]   u32 total_fixes
///   [7..10]  u32 used_bytes
///   [11]     u8  flags — bit0 enabled, bit1 state (0=STATIONARY, 1=MOVING)
///   [12..13] u16 dist_m
///   [14..15] u16 stat_hb_s
///   [16..17] u16 move_hb_s
///   [18]     u8  move_speed_kph
///   [19..20] u16 returned
///   [21]     u8  has_more
///   [22..N]  ChunkIndex × returned
class GpsTrackStatus {
  final int totalChunks;
  final int totalFixes;
  final int usedBytes;
  final bool enabled;

  /// True == MOVING, false == STATIONARY.
  final bool moving;
  final int distM;
  final int statHbS;
  final int moveHbS;
  final int moveSpeedKph;
  final bool hasMore;
  final List<GpsChunkIndex> chunks;

  const GpsTrackStatus({
    required this.totalChunks,
    required this.totalFixes,
    required this.usedBytes,
    required this.enabled,
    required this.moving,
    required this.distM,
    required this.statHbS,
    required this.moveHbS,
    required this.moveSpeedKph,
    required this.hasMore,
    required this.chunks,
  });

  static const int headerSize = 22;

  static GpsTrackStatus? parse(Uint8List frame) {
    if (frame.length < headerSize || frame[0] != respCodeGpsTrackList) {
      return null;
    }
    final r = BufferReader(frame);
    r.skipBytes(1); // response code
    final totalChunks = r.readUInt16LE();
    final totalFixes = r.readUInt32LE();
    final usedBytes = r.readUInt32LE();
    final flags = r.readUInt8();
    final distM = r.readUInt16LE();
    final statHbS = r.readUInt16LE();
    final moveHbS = r.readUInt16LE();
    final moveSpeedKph = r.readUInt8();
    final returned = r.readUInt16LE();
    final hasMore = r.readUInt8() != 0;
    final chunks = <GpsChunkIndex>[];
    for (int i = 0; i < returned; i++) {
      if (r.remaining < GpsChunkIndex.wireSize) break;
      chunks.add(GpsChunkIndex.fromReader(r));
    }
    return GpsTrackStatus(
      totalChunks: totalChunks,
      totalFixes: totalFixes,
      usedBytes: usedBytes,
      enabled: (flags & 0x01) != 0,
      moving: (flags & 0x02) != 0,
      distM: distM,
      statHbS: statHbS,
      moveHbS: moveHbS,
      moveSpeedKph: moveSpeedKph,
      hasMore: hasMore,
      chunks: chunks,
    );
  }

  /// Same status header with a different (fully-paged) chunk list.
  GpsTrackStatus withChunks(List<GpsChunkIndex> allChunks) => GpsTrackStatus(
    totalChunks: totalChunks,
    totalFixes: totalFixes,
    usedBytes: usedBytes,
    enabled: enabled,
    moving: moving,
    distM: distM,
    statHbS: statHbS,
    moveHbS: moveHbS,
    moveSpeedKph: moveSpeedKph,
    hasMore: hasMore,
    chunks: allChunks,
  );
}
