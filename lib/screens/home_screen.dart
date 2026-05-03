import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:math';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../services/server_service.dart';
import '../services/discovery_service.dart';
import '../utils/network_utils.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedDirectoryPath;
  String? _localIp;
  ServerService? _serverService;
  bool _isServerRunning = false;
  String? _currentPin;
  List<String> _serverLogs = [];
  DiscoveryService? _discoveryService;
  List<DiscoveredVault> _nearbyVaults = [];

  @override
  void initState() {
    super.initState();
    _fetchLocalIp();
    _discoveryService = DiscoveryService();
    _discoveryService!.vaultsStream.listen((vaults) {
      if (mounted) {
        setState(() {
          _nearbyVaults = vaults;
        });
      }
    });
  }

  Future<void> _fetchLocalIp() async {
    final ip = await NetworkUtils.getLocalIpAddress();
    setState(() {
      _localIp = ip;
    });
  }

  Future<void> _pickDirectory() async {
    bool hasPermission = await NetworkUtils.requestPermissions();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage permission is required to share files')),
        );
      }
      return;
    }

    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      setState(() {
        _selectedDirectoryPath = selectedDirectory;
      });
    }
  }

  void _toggleServer() async {
    if (_isServerRunning) {
      _serverService?.stopServer();
      _discoveryService?.stop();
      setState(() {
        _isServerRunning = false;
        _serverLogs.clear();
      });
    } else {
      if (_selectedDirectoryPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a directory first')),
        );
        return;
      }

      if (_localIp == null) {
        await _fetchLocalIp();
        if (_localIp == null) {
           if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not get local IP address. Please check your WiFi connection.')),
             );
           }
           return;
        }
      }

      final random = Random();
      final pin = (1000 + random.nextInt(9000)).toString();

      _serverService = ServerService(_selectedDirectoryPath!, pin, onLog: (msg) {
        if (mounted) {
          setState(() {
            final time = "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}";
            _serverLogs.insert(0, "[$time] $msg");
            if (_serverLogs.length > 50) _serverLogs.removeLast();
          });
        }
      });
      
      try {
        await _serverService!.startServer();
        _discoveryService!.start(_localIp!, _serverService!.port);
        setState(() {
          _isServerRunning = true;
          _currentPin = pin;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to start server: $e')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _serverService?.stopServer();
    _discoveryService?.stop();
    super.dispose();
  }

  Future<void> _sendFileToVault(DiscoveredVault vault) async {
    String? peerPin;
    await showDialog(
      context: context,
      builder: (context) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: Text('Connect to \${vault.ip}'),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: "Enter 4-digit PIN"),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(onPressed: () { peerPin = ctrl.text; Navigator.pop(context); }, child: const Text('Connect')),
          ],
        );
      }
    );

    if (peerPin == null || peerPin!.isEmpty) return;

    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;

    File file = File(result.files.single.path!);
    
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sending to \${vault.ip}...')));

    try {
      var request = http.MultipartRequest('POST', Uri.parse('http://\${vault.ip}:\${vault.port}/upload'));
      request.headers['X-Vault-Pin'] = peerPin!;
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      var response = await request.send();
      if (mounted) {
        if (response.statusCode == 200 || response.statusCode == 303 || response.statusCode == 302) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File sent successfully!')));
        } else {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed: Incorrect PIN.')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: \$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverUrl = _isServerRunning && _localIp != null 
        ? 'http://$_localIp:${_serverService!.port}' 
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi Vault'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Indicator
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: _isServerRunning ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isServerRunning ? Colors.green : Colors.grey,
                  width: 2,
                )
              ),
              child: Column(
                children: [
                  Icon(
                    _isServerRunning ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                    size: 48,
                    color: _isServerRunning ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isServerRunning ? 'Server is Running' : 'Server is Stopped',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _isServerRunning ? Colors.green[700] : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),

            // Directory Selection
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Shared Directory',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _selectedDirectoryPath ?? 'No directory selected',
                            style: TextStyle(
                              color: _selectedDirectoryPath == null ? Colors.grey : Colors.black87,
                              fontStyle: _selectedDirectoryPath == null ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _isServerRunning ? null : _pickDirectory,
                          icon: const Icon(Icons.folder_open),
                          color: Theme.of(context).primaryColor,
                          tooltip: 'Select Directory',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Server Controls
            ElevatedButton.icon(
              onPressed: _toggleServer,
              icon: Icon(_isServerRunning ? Icons.stop : Icons.play_arrow),
              label: Text(_isServerRunning ? 'Stop Server' : 'Start Server', style: const TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isServerRunning ? Colors.red : Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),

            const SizedBox(height: 32),

            // URL and QR Code Display
            if (_isServerRunning && serverUrl != null) ...[
              const Divider(),
              const SizedBox(height: 16),
              
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange, width: 2),
                ),
                child: Column(
                  children: [
                    const Text('Security PIN', style: TextStyle(fontSize: 16, color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      _currentPin ?? '----',
                      style: const TextStyle(fontSize: 36, letterSpacing: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                'Access your files from any device on the same WiFi network:',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  serverUrl,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: QrImageView(
                  data: serverUrl,
                  version: QrVersions.auto,
                  size: 200.0,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Scan the QR code or type the URL in your browser.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),

              if (_isServerRunning && _nearbyVaults.isNotEmpty) ...[
                const SizedBox(height: 32),
                const Text(
                  '📡 Nearby Vaults',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ..._nearbyVaults.map((vault) => Card(
                  color: Colors.blue.withOpacity(0.05),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.blue, width: 1),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.phone_android, color: Colors.blue, size: 36),
                    title: Text(vault.ip, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('Tap to send file directly'),
                    trailing: ElevatedButton.icon(
                      onPressed: () => _sendFileToVault(vault),
                      icon: const Icon(Icons.send, size: 16),
                      label: const Text('Send'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                )).toList(),
              ],

              const SizedBox(height: 32),
              
              const Text(
                'Live Connection Logs',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Container(
                height: 200,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade800),
                ),
                child: _serverLogs.isEmpty
                    ? const Center(
                        child: Text(
                          'Waiting for connections...',
                          style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _serverLogs.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Text(
                              _serverLogs[index],
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontFamily: 'monospace',
                                fontSize: 13,
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
            ] else if (!_isServerRunning) ...[
              Center(
                child: Text(
                  'Local IP: ${_localIp ?? "Detecting..."}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
