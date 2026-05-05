import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';

class ChatService {
  final List<WebSocket> _clients = [];
  final List<Map<String, dynamic>> _history = [];
  // Use a late-initialized broadcast controller so we can recreate it on dispose+reuse
  late StreamController<List<Map<String, dynamic>>> _controller;

  ChatService() {
    _controller = StreamController.broadcast();
  }

  int get clientCount => _clients.length;
  Stream<List<Map<String, dynamic>>> get messagesStream => _controller.stream;
  List<Map<String, dynamic>> get currentHistory => List.unmodifiable(_history);

  /// Upgrades an [HttpRequest] to a WebSocket connection and registers the client.
  Future<void> handleUpgrade(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    final senderIp = request.connectionInfo?.remoteAddress.address ?? 'Unknown';
    _clients.add(socket);

    // Send existing history to the newly connected client so they see context
    for (final msg in _history) {
      try { socket.add(jsonEncode(msg)); } catch (_) {}
    }

    // Add join notification to history and broadcast to all
    _addSystemMessage('$senderIp joined the vault chat', exclude: socket);

    socket.listen(
      (data) {
        try {
          final decoded = jsonDecode(data as String) as Map<String, dynamic>;
          final text = (decoded['text'] as String? ?? '').trim();
          if (text.isEmpty) return;

          final msg = {
            'type': 'message',
            'sender': senderIp,
            'text': text,
            'timestamp': DateTime.now().toIso8601String(),
          };

          _addToHistory(msg);
          _broadcast(jsonEncode(msg));
        } catch (e) {
          debugPrint('Chat parse error: $e');
        }
      },
      onDone: () {
        _clients.remove(socket);
        _addSystemMessage('$senderIp left the chat');
      },
      onError: (_) => _clients.remove(socket),
      cancelOnError: true,
    );
  }

  void _addToHistory(Map<String, dynamic> msg) {
    if (_history.length >= 100) _history.removeAt(0);
    _history.add(msg);
    if (!_controller.isClosed) _controller.add(currentHistory);
  }

  void _broadcast(String message, {WebSocket? exclude}) {
    final dead = <WebSocket>[];
    for (final client in _clients) {
      if (client == exclude) continue;
      try {
        client.add(message);
      } catch (_) {
        dead.add(client);
      }
    }
    _clients.removeWhere(dead.contains);
  }

  void _addSystemMessage(String text, {WebSocket? exclude}) {
    final msg = {
      'type': 'system',
      'text': text,
      'timestamp': DateTime.now().toIso8601String(),
    };
    // Save to history so late-joining clients see join/leave events
    _addToHistory(msg);
    // Also broadcast to currently connected clients (excluding the sender if specified)
    _broadcast(jsonEncode(msg), exclude: exclude);
  }

  void sendMessageFromHost(String text) {
    if (text.trim().isEmpty) return;
    final msg = {
      'type': 'message',
      'sender': 'Host',
      'text': text.trim(),
      'timestamp': DateTime.now().toIso8601String(),
    };
    _addToHistory(msg);
    _broadcast(jsonEncode(msg));
  }

  void dispose() {
    for (final c in _clients) {
      try { c.close(); } catch (_) {}
    }
    _clients.clear();
    _history.clear();
    if (!_controller.isClosed) {
      _controller.add([]);
      _controller.close();
    }
    // Recreate so the stream is usable on the next server start
    _controller = StreamController.broadcast();
  }
}
