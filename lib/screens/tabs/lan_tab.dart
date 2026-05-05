import 'package:flutter/material.dart';
import '../../services/scanner_service.dart';
import '../../utils/network_utils.dart';

class LanTab extends StatefulWidget {
  const LanTab({super.key});

  @override
  State<LanTab> createState() => _LanTabState();
}

class _LanTabState extends State<LanTab> {
  bool _isScanning = false;
  List<ScanResult> _devices = [];
  String? _localIp;

  @override
  void initState() {
    super.initState();
    _fetchIpAndScan();
  }

  Future<void> _fetchIpAndScan() async {
    final ip = await NetworkUtils.getLocalIpAddress();
    if (mounted) {
      setState(() => _localIp = ip);
      if (ip != null) _startScan();
    }
  }

  Future<void> _startScan() async {
    if (_localIp == null || _isScanning) return;
    setState(() {
      _isScanning = true;
      _devices = [];
    });

    final results = await ScannerService.scanSubnet(_localIp!);
    
    if (mounted) {
      setState(() {
        _isScanning = false;
        _devices = results;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Radar'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isScanning ? null : _startScan,
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 60,
                      height: 60,
                      child: CircularProgressIndicator(
                        value: _isScanning ? null : 1.0,
                        strokeWidth: 2,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                      ),
                    ),
                    Icon(
                      Icons.radar_rounded,
                      size: 32,
                      color: _isScanning ? Colors.greenAccent : Colors.white54,
                    ),
                  ],
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isScanning ? 'Scanning Subnet...' : 'Scan Complete',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Local IP: ${_localIp ?? "Detecting..."}',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10),
          Expanded(
            child: _devices.isEmpty && !_isScanning
                ? const Center(child: Text('No other devices found on this subnet.', style: TextStyle(color: Colors.white54)))
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            device.hostname.toLowerCase().contains('mac') 
                                ? Icons.laptop_mac_rounded 
                                : Icons.desktop_windows_rounded,
                            color: Colors.white70,
                          ),
                        ),
                        title: Text(device.ip, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(device.hostname.isEmpty ? 'Unknown Device' : device.hostname),
                        trailing: Text('${device.responseMs} ms', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
