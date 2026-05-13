import 'package:flutter/material.dart';

class AppTheme {
  // Renklerimiz (Sabitler)
  static const Color primaryColor = Color(0xFF2E406E); // Lacivert
  static const Color secondaryColor = Color(0xFF7FB060); // Yeşil

  // Temayı döndüren fonksiyon
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      
      // Renk Şeması
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        secondary: secondaryColor,
      ),

      // AppBar Teması (Tüm sayfalarda aynı olsun diye)
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),

      // Buton Teması
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      
      // Input (TextField) Teması
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        prefixIconColor: primaryColor,
      ),
    );
  }
}