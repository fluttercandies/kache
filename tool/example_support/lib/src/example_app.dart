import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kache_flutter/kache_flutter.dart';

import 'example_theme.dart';
import 'runtime.dart';

/// Creates an example runtime.
typedef ExampleRuntimeFactory = Future<ExampleRuntime> Function();

/// Builds one adapter-specific screen from an initialized runtime.
typedef ExampleRuntimeBuilder =
    Widget Function(BuildContext context, ExampleRuntime runtime);

/// Shared application shell that owns asynchronous runtime initialization.
class KacheExampleApp extends StatelessWidget {
  /// Creates an example application for one adapter.
  const KacheExampleApp({
    required this.adapterName,
    required this.boxName,
    required this.builder,
    this.runtimeFactory,
    super.key,
  });

  /// Adapter label shown in startup states and the window title.
  final String adapterName;

  /// Persistent Hive box name used by the default runtime factory.
  final String boxName;

  /// Adapter-specific content builder.
  final ExampleRuntimeBuilder builder;

  /// Optional deterministic runtime factory used by tests.
  final ExampleRuntimeFactory? runtimeFactory;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Kache Lab · $adapterName',
    debugShowCheckedModeBanner: false,
    theme: buildKacheExampleTheme(Brightness.light),
    darkTheme: buildKacheExampleTheme(Brightness.dark),
    themeMode: ThemeMode.system,
    home: _RuntimeHost(
      adapterName: adapterName,
      createRuntime:
          runtimeFactory ?? () => ExampleRuntime.open(boxName: boxName),
      builder: builder,
    ),
  );
}

final class _RuntimeHost extends StatefulWidget {
  const _RuntimeHost({
    required this.adapterName,
    required this.createRuntime,
    required this.builder,
  });

  final String adapterName;
  final ExampleRuntimeFactory createRuntime;
  final ExampleRuntimeBuilder builder;

  @override
  State<_RuntimeHost> createState() => _RuntimeHostState();
}

final class _RuntimeHostState extends State<_RuntimeHost> {
  late Future<ExampleRuntime> _opening;
  ExampleRuntime? _runtime;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _startOpening();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ExampleRuntime>(
    future: _opening,
    builder: (context, snapshot) {
      final runtime = snapshot.data;
      if (runtime != null) {
        return KacheScope(
          client: runtime.client,
          child: widget.builder(context, runtime),
        );
      }
      if (snapshot.hasError) {
        return _StartupState(
          icon: Icons.storage_rounded,
          title: 'Cache startup failed',
          message:
              'Hive storage could not be opened for ${widget.adapterName}.',
          actionLabel: 'Retry startup',
          onAction: _retry,
        );
      }
      return _StartupState(
        icon: Icons.inventory_2_outlined,
        title: 'Preparing cache',
        message: 'Opening Hive storage for ${widget.adapterName}.',
        showProgress: true,
      );
    },
  );

  @override
  void dispose() {
    _generation += 1;
    final runtime = _runtime;
    _runtime = null;
    if (runtime != null) {
      _observeClose(runtime);
    }
    super.dispose();
  }

  void _retry() {
    setState(_startOpening);
  }

  void _startOpening() {
    final generation = ++_generation;
    _opening = widget.createRuntime().then((runtime) {
      if (!mounted || generation != _generation) {
        _observeClose(runtime);
        return runtime;
      }
      _runtime = runtime;
      return runtime;
    });
  }

  void _observeClose(ExampleRuntime runtime) {
    unawaited(
      runtime.close().catchError((Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'kache_example_support',
            context: ErrorDescription('while closing the example runtime'),
          ),
        );
      }),
    );
  }
}

final class _StartupState extends StatelessWidget {
  const _StartupState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.showProgress = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showProgress;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  icon,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 18),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (showProgress) ...<Widget>[
                  const SizedBox(height: 24),
                  const SizedBox(width: 140, child: LinearProgressIndicator()),
                ],
                if (actionLabel != null) ...<Widget>[
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
