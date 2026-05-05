import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import '../../services/server_service.dart';
import '../../services/discovery_service.dart';
import '../../utils/network_utils.dart';

class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Client mode state
  WebSocket? _clientSocket;
  bool _isClientConnected = false;
  String? _connectedIp;
  String? _myIp; // Our own IP so we can show our sent messages on the right
  final List<Map<String, dynamic>> _clientMessages = [];

  // Discovery (shared singleton, always running)
  List<DiscoveredVault> _nearbyVaults = [];

  @override
  void initState() {
    super.initState();
    ServerService().addListener(_onServerStateChanged);
    DiscoveryService().vaultsStream.listen((vaults) {
      if (mounted) setState(() => _nearbyVaults = vaults);
    });
    _initDiscovery();
  }

  Future<void> _initDiscovery() async {
    _myIp = await NetworkUtils.getLocalIpAddress();
    if (_myIp != null && !DiscoveryService().isRunning && ServerService().isRunning) {
      DiscoveryService().start(_myIp!, ServerService().port);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ServerService().removeListener(_onServerStateChanged);
    _clientSocket?.close();
    super.dispose();
  }

  void _onServerStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _connectToVault(String ip) async {
    final port = ServerService().port;
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connecting to $ip...')),
        );
      }
      _clientSocket = await WebSocket.connect(
        'ws://$ip:$port/ws/chat',
      ).timeout(const Duration(seconds: 5));

      setState(() {
        _isClientConnected = true;
        _connectedIp = ip;
        _clientMessages.clear();
        _clientMessages.add({
          'type': 'system',
          'text': '✅ Connected to Vault at $ip',
        });
      });

      _clientSocket!.listen(
        (data) {
          if (mounted) {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            setState(() {
              _clientMessages.add(msg);
            });
            _scrollToBottom();
          }
        },
        onDone: () => _disconnectClient('Connection closed by host.'),
        onError: (e) => _disconnectClient('Connection error: $e'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _disconnectClient(String reason) {
    _clientSocket?.close();
    _clientSocket = null;
    if (mounted) {
      setState(() {
        _isClientConnected = false;
        _connectedIp = null;
        _clientMessages.add({
          'type': 'system',
          'text': '🔴 $reason',
        });
      });
    }
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    if (_isClientConnected && _clientSocket != null) {
      // Add locally immediately so the sender can see their message on the right
      setState(() {
        _clientMessages.add({
          'type': 'message',
          'sender': _myIp ?? 'Me',
          'text': text,
          'timestamp': DateTime.now().toIso8601String(),
          '_isMine': true, // local-only flag
        });
      });
      _clientSocket!.add(jsonEncode({'type': 'message', 'text': text}));
      _controller.clear();
      _scrollToBottom();
    } else if (ServerService().isRunning) {
      ServerService().chatService.sendMessageFromHost(text);
      _controller.clear();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildMessageList(List<Map<String, dynamic>> messages, bool isHostView) {
    if (messages.isEmpty) {
      return const Center(
        child: Text('No messages yet.\nSay hello! 👋', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        final isSystem = msg['type'] == 'system';
        final sender = msg['sender']?.toString() ?? '';
        final text = msg['text']?.toString() ?? '';
        final timeStr = msg['timestamp'] != null ? DateTime.tryParse(msg['timestamp'] as String) : null;
        final timeText = timeStr != null
            ? '${timeStr.hour.toString().padLeft(2, '0')}:${timeStr.minute.toString().padLeft(2, '0')}'
            : '';

        // Determine if this message is from "us"
        bool isOurs;
        if (isHostView) {
          isOurs = sender == 'Host';
        } else {
          // In client mode, messages we added locally have the _isMine flag
          isOurs = msg['_isMine'] == true;
        }

        if (isSystem) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.white60)),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: isOurs ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isOurs)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0, bottom: 2),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: _colorForSender(sender),
                    child: Text(
                      sender.isNotEmpty ? sender[sender.length - 1] : '?',
                      style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              Flexible(
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isOurs ? const Color(0xFF2563EB) : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: isOurs ? const Radius.circular(18) : const Radius.circular(4),
                      bottomRight: isOurs ? const Radius.circular(4) : const Radius.circular(18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: isOurs ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      if (!isOurs && sender.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            sender == 'Host' ? '👑 Host' : '📱 $sender',
                            style: TextStyle(
                              fontSize: 11,
                              color: _colorForSender(sender),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      Text(
                        text,
                        style: const TextStyle(fontSize: 15, color: Colors.white),
                      ),
                      if (timeText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            timeText,
                            style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.45)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _colorForSender(String sender) {
    if (sender == 'Host') return Colors.amberAccent;
    final colors = [Colors.cyanAccent, Colors.greenAccent, Colors.pinkAccent, Colors.purpleAccent];
    return colors[sender.hashCode.abs() % colors.length];
  }

  Widget _buildNoServerScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('Vault Chat'), backgroundColor: Colors.transparent, elevation: 0),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.forum_rounded, size: 72, color: Colors.white24),
              const SizedBox(height: 20),
              const Text(
                'Host a chat by starting your server,\nor join a nearby Vault below.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.white70),
              ),
              const SizedBox(height: 36),
              if (_nearbyVaults.isNotEmpty) ...[
                const Text('NEARBY VAULTS', style: TextStyle(fontSize: 11, color: Colors.white38, letterSpacing: 2)),
                const SizedBox(height: 12),
                ..._nearbyVaults.map((v) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF1D4ED8),
                      child: Icon(Icons.wifi_rounded, color: Colors.white),
                    ),
                    title: Text(v.ip, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Port ${v.port}', style: const TextStyle(color: Colors.white54)),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                      onPressed: () => _connectToVault(v.ip),
                      child: const Text('Join'),
                    ),
                  ),
                )),
              ] else
                const Column(
                  children: [
                    SizedBox(height: 12),
                    CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white38),
                    SizedBox(height: 12),
                    Text('Listening for nearby vaults...', style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!ServerService().isRunning && !_isClientConnected) {
      return _buildNoServerScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: _isClientConnected
            ? Text('💬 Chat — $_connectedIp', style: const TextStyle(fontSize: 16))
            : const Text('💬 Hosting Chat'),
        backgroundColor: _isClientConnected
            ? Colors.purple.withValues(alpha: 0.15)
            : Colors.blueAccent.withValues(alpha: 0.1),
        elevation: 0,
        actions: [
          if (_isClientConnected)
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              tooltip: 'Disconnect',
              onPressed: () => _disconnectClient('You left the chat.'),
            )
          else if (ServerService().isRunning)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${ServerService().chatService.clientCount} Online',
                    style: const TextStyle(fontSize: 12, color: Colors.greenAccent),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isClientConnected
                ? _buildMessageList(_clientMessages, false)
                : StreamBuilder<List<Map<String, dynamic>>>(
                    stream: ServerService().chatService.messagesStream,
                    initialData: ServerService().chatService.currentHistory,
                    builder: (context, snapshot) {
                      return _buildMessageList(snapshot.data ?? [], true);
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              border: const Border(top: BorderSide(color: Colors.white10)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _sendMessage(),
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.07),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: _isClientConnected ? Colors.purpleAccent : Colors.blueAccent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: _sendMessage,
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.send_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
