import 'package:flutter/material.dart';

import 'views/auth_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TogetherApp());
}

class TogetherApp extends StatelessWidget {
  const TogetherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'together',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const AuthScreen(),
    );
  }
}
