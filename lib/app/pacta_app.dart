import 'package:flutter/material.dart';
import 'package:pacta/app/chain_theme.dart';
import 'package:pacta/auth/auth_gate.dart';

class PactaApp extends StatelessWidget {
  const PactaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pacta',
      debugShowCheckedModeBanner: false,
      theme: buildChainTheme(),
      home: const AuthGate(),
    );
  }
}
