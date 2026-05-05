import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';

class EmergencyAlert {
  final String senderIp;
  final String message;
  final DateTime receivedAt;

  EmergencyAlert({
    required this.senderIp,
    required this.message,
    required this.receivedAt,
  });
}

/// SOS Beacon Service — broadcasts emergency alerts over LAN using UDP.
/// Every device running the app passively listens on port 8083.
/// When the SOS button is pressed, a UDP broadcast reaches all devices instantly,
/// completely independent of the file server.
///
/// CN Concepts: UDP broadcast, stateless datagram delivery, LAN peer discovery.
class EmergencyService {
  static final EmergencyService _instance = EmergencyService._internal();
  factory EmergencyService() => _instance;
  EmergencyService._internal() {
    _startListening();
  }

  static const int _port = 8083;
  static const String _prefix = 'SOS_BEACON:';

  RawDatagramSocket? _socket;
  final StreamController<EmergencyAlert> _alertController =
      StreamController<EmergencyAlert>.broadcast();

  Stream<EmergencyAlert> get alertStream => _alertController.stream;

  // ── Passive Listener (always on) ──────────────────────────────────────────
  Future<void> _startListening() async {
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _port,
        reuseAddress: true,
        reusePort: false,
      );
      _socket!.broadcastEnabled = true;
      _socket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket!.receive();
          if (datagram != null) _processPacket(datagram);
        }
      });
      debugPrint('EmergencyService: listening on UDP port $_port');
    } catch (e) {
      debugPrint('EmergencyService listener error: $e');
    }
  }

  void _processPacket(Datagram datagram) {
    try {
      final raw = utf8.decode(datagram.data);
      if (!raw.startsWith(_prefix)) return;
      final payload = raw.substring(_prefix.length);
      // payload format: "<senderIp>|<message>"
      final sepIdx = payload.indexOf('|');
      if (sepIdx < 0) return;
      final senderIp = payload.substring(0, sepIdx);
      final message = payload.substring(sepIdx + 1);
      if (message.isEmpty) return;

      _alertController.add(EmergencyAlert(
        senderIp: senderIp,
        message: message,
        receivedAt: DateTime.now(),
      ));
      debugPrint('EmergencyService: SOS received from $senderIp → "$message"');
    } catch (e) {
      debugPrint('EmergencyService parse error: $e');
    }
  }

  // ── Broadcast ──────────────────────────────────────────────────────────────
  Future<bool> broadcast(String localIp, String message) async {
    if (message.trim().isEmpty) return false;
    final payload = '$_prefix$localIp|${message.trim()}';
    final data = utf8.encode(payload);

    try {
      final sendSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sendSocket.broadcastEnabled = true;

      // Derive all subnet broadcast addresses from active interfaces
      final targets = <InternetAddress>[InternetAddress('255.255.255.255')];
      try {
        final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            final parts = addr.address.split('.');
            if (parts.length == 4 &&
                (addr.address.startsWith('192.168.') ||
                 addr.address.startsWith('10.') ||
                 addr.address.startsWith('172.'))) {
              parts[3] = '255';
              targets.add(InternetAddress(parts.join('.')));
            }
          }
        }
      } catch (_) {}

      for (final target in targets) {
        try { sendSocket.send(data, target, _port); } catch (_) {}
      }
      sendSocket.close();
      debugPrint('EmergencyService: SOS broadcast sent from $localIp — "$message"');
      return true;
    } catch (e) {
      debugPrint('EmergencyService broadcast error: $e');
      return false;
    }
  }

  void dispose() {
    _socket?.close();
    _alertController.close();
  }
}
