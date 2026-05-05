import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../services/emergency_service.dart';
import '../../utils/network_utils.dart';

class SosBeaconTab extends StatefulWidget {
  const SosBeaconTab({super.key});

  @override
  State<SosBeaconTab> createState() => _SosBeaconTabState();
}

class _SosBeaconTabState extends State<SosBeaconTab>
    with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController(
    text: 'EMERGENCY! Need immediate help!',
  );

  bool _isSending = false;
  String? _localIp;

  // Pulse animation for the SOS button
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _fetchIp();
  }

  Future<void> _fetchIp() async {
    final ip = await NetworkUtils.getLocalIpAddress();
    if (mounted) setState(() => _localIp = ip);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendSOS() async {
    if (_localIp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not determine your IP. Connect to WiFi first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final msg = _messageController.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an emergency message.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSending = true);

    // Strong haptic at the moment of sending
    HapticFeedback.heavyImpact();

    final success = await EmergencyService().broadcast(_localIp!, msg);

    if (mounted) {
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? '🚨 SOS Broadcast sent to all devices on this network!'
              : '❌ Failed to broadcast. Check your WiFi connection.'),
          backgroundColor: success ? const Color(0xFF991B1B) : Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.crisis_alert_rounded, color: Colors.redAccent, size: 22),
            SizedBox(width: 10),
            Text('SOS Beacon'),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.broadcast_on_personal_rounded,
                      color: Colors.redAccent, size: 36),
                  const SizedBox(height: 12),
                  const Text(
                    'Emergency Broadcast',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Instantly alerts ALL devices on this WiFi network. '
                    'Each device will receive a flashing alarm with your message.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
                  ),
                  if (_localIp != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Broadcasting from: $_localIp',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white38,
                            fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Message input
            const Text(
              'EMERGENCY MESSAGE',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.white38,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _messageController,
              maxLines: 3,
              maxLength: 140,
              style: const TextStyle(fontSize: 16, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Type your emergency message...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.redAccent),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.red.withValues(alpha: 0.2)),
                ),
                counterStyle: const TextStyle(color: Colors.white38),
              ),
            ),

            const SizedBox(height: 40),

            // SOS Pulse Button
            Center(
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (context, child) => Transform.scale(
                  scale: _isSending ? 1.0 : _pulseAnim.value,
                  child: child,
                ),
                child: GestureDetector(
                  onTap: _isSending ? null : _sendSOS,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.red.shade600,
                          Colors.red.shade900,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.5),
                          blurRadius: 40,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: _isSending
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.sos_rounded,
                                  color: Colors.white, size: 64),
                              SizedBox(height: 4),
                              Text(
                                'SEND ALERT',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Warning disclaimer
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Colors.amber.withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.amber, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Only use in genuine emergencies. This alert reaches ALL '
                      'devices on the same WiFi instantly.',
                      style: TextStyle(fontSize: 12, color: Colors.amber),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
