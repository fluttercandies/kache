import 'package:flutter/material.dart';

void main() {
  runApp(const KacheFlutterExampleApp());
}

class KacheFlutterExampleApp extends StatelessWidget {
  const KacheFlutterExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('Kache Flutter'))),
    );
  }
}
