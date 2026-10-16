import 'package:flutter/material.dart';

class AppColors {
  // Dark Backgrounds
  static const Color background = Color(0xFF0F172A); // Slate 900
  static const Color surface = Color(0xFF1E293B);    // Slate 800
  static const Color surfaceLight = Color(0xFF334155); // Slate 700
  static const Color surfaceBorder = Color(0xFF475569); // Slate 600

  // Brand Accents
  static const Color primary = Color(0xFF3B82F6);    // Blue 500
  static const Color primaryDark = Color(0xFF1D4ED8); // Blue 700
  static const Color accent = Color(0xFF06B6D4);     // Cyan 500

  // Status Colors
  static const Color completed = Color(0xFF10B981);  // Emerald 500
  static const Color completedBg = Color(0xFF064E3B);
  static const Color active = Color(0xFF3B82F6);     // Blue 500
  static const Color grace = Color(0xFFF59E0B);      // Amber 500
  static const Color graceBg = Color(0xFF78350F);
  static const Color paused = Color(0xFF94A3B8);     // Slate 400
  static const Color alarm = Color(0xFFEF4444);      // Red 500
  static const Color alarmBg = Color(0xFF7F1D1D);
  static const Color emergency = Color(0xFF8B5CF6);  // Purple 500
  static const Color emergencyBg = Color(0xFF4C1D95);

  // Text Colors
  static const Color textPrimary = Color(0xFFF8FAFC);   // Slate 50
  static const Color textSecondary = Color(0xFF94A3B8); // Slate 400
  static const Color textMuted = Color(0xFF64748B);     // Slate 500

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient alarmGradient = LinearGradient(
    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient emergencyGradient = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
