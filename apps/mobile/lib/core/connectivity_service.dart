import "dart:async";

import "package:connectivity_plus/connectivity_plus.dart";

/// Connection state machine for offline-first UI (Stage N).
///
/// States are explicit so the app can render honest status:
/// offline (no interface up) / reconnecting (interface up, last request failed)
/// / online (recent request succeeded).
enum ConnectState { online, offline, reconnecting }

class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity {
    _init();
  }

  final Connectivity? _connectivity;
  final _stateController = StreamController<ConnectState>.broadcast();
  ConnectState _state = ConnectState.online;

  ConnectState get state => _state;
  Stream<ConnectState> get stream => _stateController.stream;

  final List<void Function()> _restoreCallbacks = [];

  void _init() {
    final c = _connectivity;
    if (c == null) return; // Tests: no plugin available.
    c.onConnectivityChanged.listen((results) {
      final hasInterface = results.any((r) => r != ConnectivityResult.none);
      if (hasInterface && _state != ConnectState.online) {
        _state = ConnectState.reconnecting;
        _stateController.add(_state);
        for (final cb in _restoreCallbacks) {
          try {
            cb();
          } catch (_) {}
        }
      } else if (!hasInterface) {
        _state = ConnectState.offline;
        _stateController.add(_state);
      }
    });
  }

  /// Called by the API layer when a request clearly succeeded — upgrades
  /// reconnecting → online.
  void markAlive() {
    if (_state != ConnectState.online) {
      _state = ConnectState.online;
      _stateController.add(_state);
    }
  }

  /// Called by the API layer on network failure with an interface up —
  /// downgrades to reconnecting (not offline, since the interface exists).
  void markUnreachable() {
    if (_state == ConnectState.online) {
      _state = ConnectState.reconnecting;
      _stateController.add(_state);
    }
  }

  void onRestored(void Function() cb) => _restoreCallbacks.add(cb);

  void dispose() => _stateController.close();
}
