import 'package:flutter/material.dart';

void main() {
  runApp(const KacheBlocExampleApp());
}

class KacheBlocExampleApp extends StatelessWidget {
  const KacheBlocExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('Kache Bloc'))),
    );
  }
}
