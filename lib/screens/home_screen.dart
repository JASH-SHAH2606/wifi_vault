import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'tabs/server_tab.dart';
import 'tabs/lan_tab.dart';
import 'tabs/chat_tab.dart';
import 'tabs/speed_test_tab.dart';
import 'tabs/sos_tab.dart';
import 'tabs/stats_tab.dart';
import '../services/emergency_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  StreamSubscription<EmergencyAlert>? _alertSub;

  // Flashing animation for the alert overlay
  late AnimationController _flashController;
  late Animation<Color?> _flashColor;

  // Haptic feedback timer
  Timer? _hapticTimer;

  final List<Widget> _tabs = [
    const ServerTab(),
    const LanTab(),
    const SpeedTestTab(),
    const ChatTab(),
    const SosBeaconTab(),
    const StatsTab(),
  ];

  @override
  void initState() {
    super.initState();

    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _flashColor = ColorTween(
      begin: const Color(0xFF7F1D1D), // deep red
      end: const Color(0xFFFF0000),   // bright red
    ).animate(_flashController);

    // Start listening for incoming SOS alerts
    _alertSub = EmergencyService().alertStream.listen(_onAlertReceived);
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    _hapticTimer?.cancel();
    _flashController.dispose();
    super.dispose();
  }

  void _onAlertReceived(EmergencyAlert alert) {
    if (!mounted) return;
    _showEmergencyOverlay(alert);
  }

  void _showEmergencyOverlay(EmergencyAlert alert) {
    // Start rapid haptic feedback
    _flashController.repeat(reverse: true);
    _hapticTimer?.cancel();
    _hapticTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      HapticFeedback.heavyImpact();
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (context) => PopScope(
        canPop: false, // Cannot dismiss with back button
        child: AnimatedBuilder(
          animation: _flashColor,
          builder: (context, child) => Dialog(
            backgroundColor: _flashColor.value,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.all(16),
            child: child,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Flashing SOS icon
                AnimatedBuilder(
                  animation: _flashController,
                  builder: (context, _) => Icon(
                    Icons.sos_rounded,
                    size: 80,
                    color: _flashController.value > 0.5
                        ? Colors.white
                        : Colors.yellow,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '🚨  EMERGENCY ALERT  🚨',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'From: ${alert.senderIp}',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    alert.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red.shade800,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      _flashController.stop();
                      _flashController.reset();
                      _hapticTimer?.cancel();
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      'DISMISS',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF1E293B),
        selectedItemColor: const Color(0xFF60A5FA),
        unselectedItemColor: const Color(0xFF94A3B8),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dns_rounded),
            label: 'Server',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.radar_rounded),
            label: 'LAN Scan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.speed_rounded),
            label: 'Speed Test',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.chat_bubble_2_fill),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.crisis_alert_rounded, color: Colors.redAccent),
            label: 'SOS',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics_rounded),
            label: 'Stats',
          ),
        ],
      ),
    );
  }
}
