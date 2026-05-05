import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/server_service.dart';

class SpeedTestTab extends StatefulWidget {
  const SpeedTestTab({super.key});

  @override
  State<SpeedTestTab> createState() => _SpeedTestTabState();
}

class _SpeedTestTabState extends State<SpeedTestTab> {
  Timer? _timer;
  int _lastBytesIn = 0;
  int _lastBytesOut = 0;
  double _currentMbpsIn = 0.0;
  double _currentMbpsOut = 0.0;

  @override
  void initState() {
    super.initState();
    ServerService().addListener(_onServerStateChanged);
    _checkServerState();
  }

  void _onServerStateChanged() {
    if (mounted) {
      _checkServerState();
      setState(() {});
    }
  }

  void _checkServerState() {
    if (ServerService().isRunning) {
      final stats = ServerService().statsService.getStats();
      _lastBytesIn = stats['bytesIn'] as int;
      _lastBytesOut = stats['bytesOut'] as int;
      _timer ??= Timer.periodic(const Duration(seconds: 1), _updateSpeeds);
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    ServerService().removeListener(_onServerStateChanged);
    _timer?.cancel();
    super.dispose();
  }

  void _updateSpeeds(Timer t) {
    if (!mounted || !ServerService().isRunning) return;
    final stats = ServerService().statsService.getStats();
    final bytesIn = stats['bytesIn'] as int;
    final bytesOut = stats['bytesOut'] as int;

    final deltaIn = bytesIn - _lastBytesIn;
    final deltaOut = bytesOut - _lastBytesOut;

    setState(() {
      _currentMbpsIn = (deltaIn * 8) / 1000000;
      _currentMbpsOut = (deltaOut * 8) / 1000000;
      _lastBytesIn = bytesIn;
      _lastBytesOut = bytesOut;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ServerService().isRunning) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live Bandwidth')),
        body: const Center(
          child: Text('Start the server to monitor bandwidth.', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Bandwidth Monitor'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSpeedGauge('Download (Client -> Host)', _currentMbpsIn, Colors.greenAccent),
            const SizedBox(height: 40),
            _buildSpeedGauge('Upload (Host -> Client)', _currentMbpsOut, Colors.blueAccent),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedGauge(String label, double mbps, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 16, color: Colors.white70)),
        const SizedBox(height: 16),
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 180,
              height: 180,
              child: CircularProgressIndicator(
                value: (mbps / 100).clamp(0.0, 1.0), // Scale to 100 Mbps max visually
                strokeWidth: 12,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            Column(
              children: [
                Text(
                  mbps.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const Text('Mbps', style: TextStyle(fontSize: 16, color: Colors.white54)),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
