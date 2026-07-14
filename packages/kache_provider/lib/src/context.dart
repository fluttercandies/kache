import 'package:flutter/widgets.dart';
import 'package:kache_flutter/kache_flutter.dart';
import 'package:provider/provider.dart';

/// Provider-specific cache lookups for a [BuildContext].
extension KacheProviderContext on BuildContext {
  /// Reads the nearest controller without subscribing to changes.
  KacheController<T> readKache<T>() => read<KacheController<T>>();

  /// Watches the nearest controller and returns its current snapshot.
  KacheSnapshot<T> watchKache<T>() => watch<KacheController<T>>().value;
}
