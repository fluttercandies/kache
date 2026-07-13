import 'package:flutter/material.dart';

void main() {
  runApp(const KacheRiverpodExampleApp());
}

class KacheRiverpodExampleApp extends StatelessWidget {
  const KacheRiverpodExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('Kache Riverpod'))),
    );
  }
}
