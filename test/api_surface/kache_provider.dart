import 'package:flutter/widgets.dart';
import 'package:kache_provider/kache_provider.dart';

void verifyProviderTypes({
  required KacheProvider<int> provider,
  required KacheConsumer<int> consumer,
}) {}

KacheController<int> verifyReadExtension(BuildContext context) =>
    context.readKache<int>();

KacheSnapshot<int> verifyWatchExtension(BuildContext context) =>
    context.watchKache<int>();
