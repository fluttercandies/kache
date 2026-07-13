import 'package:flutter/material.dart';

void main() {
  runApp(const KacheProviderExampleApp());
}

class KacheProviderExampleApp extends StatelessWidget {
  const KacheProviderExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('Kache Provider'))),
    );
  }
}
