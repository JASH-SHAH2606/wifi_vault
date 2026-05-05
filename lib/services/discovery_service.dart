import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';

class DiscoveredVault {
  final String ip;
  final int port;
  final DateTime lastSeen;

  DiscoveredVault(this.ip, this.port, this.lastSeen);
}

/// Singleton service for LAN vault discovery.
/// Separates two independent concerns:
///   1. Broadcasting — advertises THIS device's vault to the LAN (only when server is running)
///   2. Listening — always passively receives broadcasts from other vaults
class DiscoveryService {
  static final DiscoveryService _instance = DiscoveryService._internal();
  factory DiscoveryService() => _instance;
  DiscoveryService._internal() {
    _startListening();
  }

  static const int _broadcastPort = 8081;
  RawDatagramSocket? _listenSocket;
  RawDatagramSocket? _broadcastSocket;
  Timer? _broadcastTimer;
  bool _isBroadcasting = false;
  bool get isRunning => _isBroadcasting;

  final Map<String, DiscoveredVault> _discoveredVaults = {};
  final StreamController<List<DiscoveredVault>> _vaultsController =
      StreamController<List<DiscoveredVault>>.broadcast();

  Stream<List<DiscoveredVault>> get vaultsStream => _vaultsController.stream;
  List<DiscoveredVault> get currentVaults => _discoveredVaults.values.toList();

  // ── Passive Listener (always on) ────────────────────────────────────────
  Future<void> _startListening() async {
    try {
      _listenSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _broadcastPort,
        reuseAddress: true,
        reusePort: false,
      );
      _listenSocket!.broadcastEnabled = true;
      _listenSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _listenSocket!.receive();
          if (datagram != null) _processPacket(datagram);
        }
      });
      debugPrint('DiscoveryService: passive listener started on port $_broadcastPort');
    } catch (e) {
      debugPrint('DiscoveryService listener error: $e');
    }
  }

  void _processPacket(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      if (!message.startsWith('WIFI_VAULT:')) return;
      final parts = message.split(':');
      if (parts.length != 3) return;
      final ip = parts[1];
      final port = int.tryParse(parts[2]);
      if (port == null) return;
      _discoveredVaults[ip] = DiscoveredVault(ip, port, DateTime.now());
      _cleanupOldVaults();
      _vaultsController.add(_discoveredVaults.values.toList());
    } catch (e) {
      debugPrint('DiscoveryService packet parse error: $e');
    }
  }

  // ── Active Broadcaster (only when server is live) ────────────────────────
  Future<void> start(String localIp, int serverPort) async {
    if (_isBroadcasting) return; // Already broadcasting, don't double-bind
    _isBroadcasting = true;

    try {
      _broadcastSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _broadcastSocket!.broadcastEnabled = true;

      _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        final message = 'WIFI_VAULT:$localIp:$serverPort';
        final data = utf8.encode(message);

        // Global broadcast
        try { _broadcastSocket!.send(data, InternetAddress('255.255.255.255'), _broadcastPort); } catch (_) {}

        // Subnet-specific broadcast (derived from actual IP)
        try {
          final parts = localIp.split('.');
          if (parts.length == 4) {
            parts[3] = '255';
            _broadcastSocket!.send(data, InternetAddress(parts.join('.')), _broadcastPort);
          }
        } catch (_) {}
      });
      debugPrint('DiscoveryService: broadcasting as $localIp:$serverPort');
    } catch (e) {
      _isBroadcasting = false;
      debugPrint('DiscoveryService broadcast error: $e');
    }
  }

  void stop() {
    _isBroadcasting = false;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _broadcastSocket?.close();
    _broadcastSocket = null;
    _discoveredVaults.clear();
    if (!_vaultsController.isClosed) _vaultsController.add([]);
    debugPrint('DiscoveryService: broadcasting stopped (listener stays active)');
  }

  void _cleanupOldVaults() {
    final now = DateTime.now();
    _discoveredVaults.removeWhere(
      (ip, vault) => now.difference(vault.lastSeen).inSeconds > 12,
    );
  }
}
