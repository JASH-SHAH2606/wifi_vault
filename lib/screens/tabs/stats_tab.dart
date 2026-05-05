import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/server_service.dart';

class StatsTab extends StatefulWidget {
  const StatsTab({super.key});

  @override
  State<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<StatsTab> {
  Timer? _timer;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    ServerService().addListener(_onServerStateChanged);
    _checkServerState();
  }

  void _onServerStateChanged() {
    if (mounted) {
      setState(() {
        _checkServerState();
      });
    }
  }

  void _checkServerState() {
    if (ServerService().isRunning) {
      _fetchStats();
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _fetchStats());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _fetchStats() {
    if (mounted && ServerService().isRunning) {
      setState(() {
        _stats = ServerService().statsService.getStats();
        _stats['chatClients'] = ServerService().chatService.clientCount;
      });
    }
  }

  @override
  void dispose() {
    ServerService().removeListener(_onServerStateChanged);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ServerService().isRunning) {
      return Scaffold(
        appBar: AppBar(title: const Text('Network Stats')),
        body: const Center(
          child: Text('Start the server to view stats.', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Dashboard'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GridView.count(
        padding: const EdgeInsets.all(20),
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.1,
        children: [
          _buildStatCard(Icons.timer_rounded, 'Uptime', _stats['uptime']?.toString() ?? '00:00:00', Colors.purpleAccent),
          _buildStatCard(Icons.cloud_download_rounded, 'Total In', _stats['bytesInFormatted']?.toString() ?? '0 B', Colors.greenAccent),
          _buildStatCard(Icons.cloud_upload_rounded, 'Total Out', _stats['bytesOutFormatted']?.toString() ?? '0 B', Colors.blueAccent),
          _buildStatCard(Icons.people_alt_rounded, 'Unique IPs', _stats['uniqueClients']?.toString() ?? '0', Colors.orangeAccent),
          _buildStatCard(Icons.sync_alt_rounded, 'Total Requests', _stats['totalRequests']?.toString() ?? '0', Colors.pinkAccent),
          _buildStatCard(Icons.chat_bubble_rounded, 'Chat Clients', _stats['chatClients']?.toString() ?? '0', Colors.cyanAccent),
        ],
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36, color: color),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 14, color: Colors.white70)),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
