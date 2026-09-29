import 'dart:async';
import 'package:flutter/foundation.dart';

/// Cache entry with TTL (Time To Live) support
class CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  final Duration ttl;

  CacheEntry({required this.data, required this.timestamp, required this.ttl});

  bool get isExpired => DateTime.now().difference(timestamp) > ttl;
}

/// Smart caching service for web platform to minimize Supabase queries
/// Features:
/// - TTL-based cache invalidation
/// - Memory-efficient storage
/// - Automatic cleanup of expired entries
/// - Support for incremental data updates
class WebCacheService extends ChangeNotifier {
  final Map<String, CacheEntry<dynamic>> _cache = {};
  Timer? _cleanupTimer;

  // Default TTL values for different data types
  static const Duration defaultTTL = Duration(minutes: 5);
  static const Duration statisticsTTL = Duration(minutes: 2);
  static const Duration sessionsTTL = Duration(minutes: 3);
  static const Duration activitiesTTL = Duration(minutes: 5);

  WebCacheService() {
    _startCleanupTimer();
  }

  /// Start periodic cleanup of expired cache entries
  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _cleanExpiredEntries();
    });
  }

  /// Clean up expired cache entries to free memory
  void _cleanExpiredEntries() {
    final expiredKeys = <String>[];

    _cache.forEach((key, entry) {
      if (entry.isExpired) {
        expiredKeys.add(key);
      }
    });

    for (final key in expiredKeys) {
      _cache.remove(key);
      debugPrint('[CACHE] Removed expired entry: $key');
    }
  }

  /// Get cached data if available and not expired
  T? get<T>(String key) {
    final entry = _cache[key];

    if (entry == null) {
      debugPrint('[CACHE] Miss: $key');
      return null;
    }

    if (entry.isExpired) {
      debugPrint('[CACHE] Expired: $key');
      _cache.remove(key);
      return null;
    }

    debugPrint('[CACHE] Hit: $key');
    return entry.data as T;
  }

  /// Set cached data with optional custom TTL
  void set<T>(String key, T data, {Duration? ttl}) {
    _cache[key] = CacheEntry(
      data: data,
      timestamp: DateTime.now(),
      ttl: ttl ?? defaultTTL,
    );
    debugPrint('[CACHE] Set: $key (TTL: ${ttl ?? defaultTTL})');
    notifyListeners();
  }

  /// Invalidate specific cache entry
  void invalidate(String key) {
    final removed = _cache.remove(key);
    if (removed != null) {
      debugPrint('[CACHE] Invalidated: $key');
      notifyListeners();
    }
  }

  /// Invalidate multiple cache entries matching a pattern
  void invalidatePattern(String pattern) {
    final keysToRemove = <String>[];

    for (final key in _cache.keys) {
      if (key.contains(pattern)) {
        keysToRemove.add(key);
      }
    }

    for (final key in keysToRemove) {
      _cache.remove(key);
      debugPrint('[CACHE] Invalidated (pattern): $key');
    }

    if (keysToRemove.isNotEmpty) {
      notifyListeners();
    }
  }

  /// Clear all cache entries
  void clearAll() {
    _cache.clear();
    debugPrint('[CACHE] Cleared all entries');
    notifyListeners();
  }

  /// Get cache statistics for debugging
  Map<String, dynamic> getStats() {
    final now = DateTime.now();
    int validEntries = 0;
    int expiredEntries = 0;

    for (final entry in _cache.values) {
      if (entry.isExpired) {
        expiredEntries++;
      } else {
        validEntries++;
      }
    }

    return {
      'total_entries': _cache.length,
      'valid_entries': validEntries,
      'expired_entries': expiredEntries,
      'timestamp': now.toIso8601String(),
    };
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _cache.clear();
    super.dispose();
  }
}

/// Cache key generator utility
class CacheKeys {
  // Statistics keys
  static String todayDuration() => 'stats:today:duration';
  static String monthDuration() => 'stats:month:duration';
  static String allTimeDuration() => 'stats:alltime:duration';
  static String totalSessions() => 'stats:total:sessions';

  // Sessions keys
  static String monthSessions(int year, int month) => 'sessions:$year:$month';
  static String dateRangeSessions(DateTime start, DateTime end) =>
      'sessions:${start.toIso8601String()}:${end.toIso8601String()}';

  // Activities keys
  static String dateActivities(DateTime date) =>
      'activities:${date.year}:${date.month}:${date.day}';
  static String monthActivities(int year, int month) =>
      'activities:$year:$month';
}
