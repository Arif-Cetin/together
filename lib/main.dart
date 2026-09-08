import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'core/constants.dart';
import 'views/auth_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase Web Konfigürasyonu
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyAYAuTnEDwC8DWeAn0dQ7L1mC4rE7_gR3E",
      authDomain: "together-686b0.firebaseapp.com",
      databaseURL: "https://together-686b0-default-rtdb.europe-west1.firebasedatabase.app",
      projectId: "together-686b0",
      storageBucket: "together-686b0.firebasestorage.app",
      messagingSenderId: "122882155155",
      appId: "1:122882155155:web:76548ee40717367ca52366",
    ),
  );

  runApp(const TogetherApp());
}

class TogetherApp extends StatelessWidget {
  const TogetherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'together',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.bgDarkest,
      ),
      home: const AuthScreen(),
    );
  }
}
