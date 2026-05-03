import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class NetworkUtils {
  static Future<String?> getLocalIpAddress() async {
    try {
      // First, try the standard method for when connected to Wi-Fi
      final info = NetworkInfo();
      String? ip = await info.getWifiIP();
      
      // If the device is acting as a hotspot, getWifiIP() often returns null or an empty string.
      // In this case, we manually scan the device's network interfaces.
      if (ip == null || ip.isEmpty || ip == '0.0.0.0') {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLinkLocal: false,
        );
        
        // Prioritize finding a standard private local network IP (typical for hotspots)
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            if (addr.address.startsWith('192.168.') || 
                addr.address.startsWith('10.') || 
                addr.address.startsWith('172.')) {
              return addr.address;
            }
          }
        }
        
        // Fallback to any non-localhost IP if standard ones aren't found
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
             if (addr.address != '127.0.0.1') {
               return addr.address;
             }
          }
        }
      }
      return ip;
    } catch (e) {
      print("Failed to get IP: $e");
      return null;
    }
  }

  static Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      // In newer Android versions, manageExternalStorage might be required for broad access,
      // but if we are just using file_picker, SAF (Storage Access Framework) grants us 
      // URI permissions directly. However, we are running an HTTP server and accessing 
      // the raw file path, so we do need explicit read permissions.
      var storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return true;

      var manageStatus = await Permission.manageExternalStorage.request();
      if (manageStatus.isGranted) return true;

      return false;
    }
    return true; // Assume true for other platforms for now
  }
}
