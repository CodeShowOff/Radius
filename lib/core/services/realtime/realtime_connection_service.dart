import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logger/logger.dart';

/// Enum representing the connection state of real-time services.
enum RealtimeConnectionStatus {
  /// Initial state, not yet connected.
  initializing,
  
  /// Connected and receiving real-time updates.
  connected,
  
  /// Temporarily disconnected, will attempt to reconnect.
  disconnected,
  
  /// Reconnecting after a disconnect.
  reconnecting,
  
  /// Fatal error, manual intervention may be needed.
  error,
}

/// Service that monitors and manages the connection state for real-time
/// Firestore streams.
///
/// This service:
/// - Monitors network connectivity changes
/// - Provides connection status for UI feedback
/// - Triggers reconnection logic when network is restored
/// - Notifies listeners when they should refresh their streams
///
/// This enables a smooth, industry-standard user experience where:
/// - Users see instant data without loading states
/// - Real-time updates flow seamlessly
/// - Network drops are handled gracefully
/// - Reconnection happens automatically
class RealtimeConnectionService {
  final FirebaseFirestore _firestore;
  final Connectivity _connectivity;
  final Logger _logger;

  /// Stream controller for connection status changes.
  final _statusController = StreamController<RealtimeConnectionStatus>.broadcast();
  
  /// Stream controller for reconnection events.
  /// Listeners should refresh their Firestore streams when this emits.
  final _reconnectionController = StreamController<void>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  
  RealtimeConnectionStatus _currentStatus = RealtimeConnectionStatus.initializing;
  bool _wasDisconnected = false;
  bool _isDisposed = false;

  RealtimeConnectionService({
    FirebaseFirestore? firestore,
    Connectivity? connectivity,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _connectivity = connectivity ?? Connectivity(),
        _logger = logger ?? Logger();

  /// Current connection status.
  RealtimeConnectionStatus get status => _currentStatus;

  /// Stream of connection status changes.
  Stream<RealtimeConnectionStatus> get statusStream => _statusController.stream;

  /// Stream that emits when reconnection has occurred and streams should be refreshed.
  Stream<void> get onReconnection => _reconnectionController.stream;

  /// Whether the service is currently connected.
  bool get isConnected => _currentStatus == RealtimeConnectionStatus.connected;

  /// Initialize the connection monitoring.
  Future<void> initialize() async {
    _logger.i('Initializing RealtimeConnectionService');

    // Enable Firestore offline persistence for better offline experience.
    // Use a bounded cache (100 MB) to prevent unbounded disk growth that
    // would gradually slow Firestore operations over time.
    _firestore.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: 100 * 1024 * 1024, // 100 MB
    );

    // Check initial connectivity
    final initialResult = await _connectivity.checkConnectivity();
    _handleConnectivityChange(initialResult);

    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectivityChange,
      onError: (error) {
        _logger.e('Connectivity stream error', error: error);
      },
    );

    _updateStatus(RealtimeConnectionStatus.connected);
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final hasConnection = results.isNotEmpty && 
        !results.every((r) => r == ConnectivityResult.none);

    if (hasConnection) {
      if (_wasDisconnected) {
        _logger.i('Network restored, triggering reconnection');
        _handleReconnection();
      } else {
        _updateStatus(RealtimeConnectionStatus.connected);
      }
    } else {
      _logger.w('Network disconnected');
      _wasDisconnected = true;
      _updateStatus(RealtimeConnectionStatus.disconnected);
    }
  }

  void _handleReconnection() {
    if (_isDisposed) return;
    
    _updateStatus(RealtimeConnectionStatus.reconnecting);
    
    // Give Firestore a moment to re-establish connections
    Future.delayed(const Duration(milliseconds: 500), () {
      // Guard against disposal during the delay
      if (_isDisposed) return;
      
      _wasDisconnected = false;
      _updateStatus(RealtimeConnectionStatus.connected);
      
      // Notify listeners to refresh their streams if needed
      if (!_reconnectionController.isClosed) {
        _reconnectionController.add(null);
      }
      _logger.i('Reconnection complete, notified listeners');
    });
  }

  void _updateStatus(RealtimeConnectionStatus newStatus) {
    if (_isDisposed) return;
    
    if (_currentStatus != newStatus) {
      _currentStatus = newStatus;
      if (!_statusController.isClosed) {
        _statusController.add(newStatus);
      }
      _logger.d('Connection status changed to: $newStatus');
    }
  }

  /// Call this when a Firestore stream encounters an error.
  /// The service will help coordinate reconnection.
  void reportStreamError(String streamName, Object error) {
    if (_isDisposed) return;
    
    _logger.e('Stream error reported: $streamName', error: error);
    
    // If we haven't already marked as disconnected, do so now
    if (_currentStatus == RealtimeConnectionStatus.connected) {
      _updateStatus(RealtimeConnectionStatus.disconnected);
      _wasDisconnected = true;
      
      // Attempt reconnection after a brief delay
      Future.delayed(const Duration(seconds: 2), () {
        if (!_isDisposed && _wasDisconnected) {
          _handleReconnection();
        }
      });
    }
  }

  /// Manually trigger a reconnection attempt.
  void forceReconnect() {
    if (_isDisposed) return;
    
    _logger.i('Force reconnect requested');
    _wasDisconnected = true;
    _handleReconnection();
  }

  /// Dispose of resources.
  Future<void> dispose() async {
    _isDisposed = true;
    await _connectivitySubscription?.cancel();
    await _statusController.close();
    await _reconnectionController.close();
    _logger.i('RealtimeConnectionService disposed');
  }
}
