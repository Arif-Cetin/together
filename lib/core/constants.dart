import 'package:flutter/material.dart';

class AppColors {
  static const Color bgDarkest = Color(0xFF0A0712);
  static const Color bgRail = Color(0xFF07050D);
  static const Color bgSurface = Color(0xE0120D1D);

  // Neon Mor - Yeşil Paleti
  static const Color neonGreen = Color(0xFF23A55A);
  static const Color neonGreenBright = Color(0xFF57F287);
  static const Color neonPurple = Color(0xFF8A2BE2);
  static const Color neonPurpleBright = Color(0xFFC77DFF);
  static const Color danger = Color(0xFFDA373C);

  static const Color textMain = Color(0xFFF2F3F5);
  static const Color textMuted = Color(0xFF949BA4);
  static const Color glassBorder = Color(0x38C77DFF);
  static const Color glassBg = Color(0xEB161024);
  static const Color inputBg = Color(0xE60F0B18);
}

class AppConfig {
  // Şifre: K9#mX$7vL!2pQ@9z (SHA-256 Hash Karşılığı)
  static const String expectedHash =
      "4631f037cd1158e98cf9499d8bd978d3d91c2d7580b1edf993ad9aff31d7b1e9";

  // Google Ücretsiz STUN Konfigürasyonu
  static final Map<String, dynamic> rtcConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };
}
