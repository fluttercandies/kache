part of 'store.dart';

final Expando<Map<String, _HiveBoxLeaseState>> _hiveBoxLeases =
    Expando<Map<String, _HiveBoxLeaseState>>('kache_hive_box_leases');

Future<_HiveBoxLeaseHandle> _acquireHiveBox({
  required HiveInterface hive,
  required String boxName,
  required HiveCipher? encryptionCipher,
  required bool crashRecovery,
  required String? path,
  required Uint8List? bytes,
}) async {
  _validateBoxName(boxName);
  final normalizedName = boxName.toLowerCase();
  final leases = _hiveBoxLeases[hive] ??= <String, _HiveBoxLeaseState>{};
  var state = leases[normalizedName];
  if (state == null) {
    final wasOpen = hive.isBoxOpen(normalizedName);
    final boxFuture = wasOpen
        ? Future<Box<Object?>>.value(hive.box<Object?>(normalizedName))
        : hive.openBox<Object?>(
            normalizedName,
            encryptionCipher: encryptionCipher,
            crashRecovery: crashRecovery,
            path: path,
            bytes: bytes,
          );
    state = _HiveBoxLeaseState(
      boxFuture: boxFuture,
      ownsBox: !wasOpen,
      leases: leases,
      normalizedName: normalizedName,
    );
    leases[normalizedName] = state;
  }

  late final Box<Object?> box;
  try {
    box = await state.boxFuture;
  } on Object {
    if (identical(leases[normalizedName], state)) {
      leases.remove(normalizedName);
    }
    rethrow;
  }
  state.referenceCount += 1;
  return _HiveBoxLeaseHandle(state: state, box: box);
}

final class _HiveBoxLeaseState {
  _HiveBoxLeaseState({
    required this.boxFuture,
    required this.ownsBox,
    required this.leases,
    required this.normalizedName,
  });

  final Future<Box<Object?>> boxFuture;
  final bool ownsBox;
  final Map<String, _HiveBoxLeaseState> leases;
  final String normalizedName;
  int referenceCount = 0;
}

final class _HiveBoxLeaseHandle {
  _HiveBoxLeaseHandle({required this.state, required this.box});

  final _HiveBoxLeaseState state;
  final Box<Object?> box;
  bool _isReleased = false;

  bool get isOwned => state.ownsBox;

  Future<void> release() async {
    if (_isReleased) {
      return;
    }
    _isReleased = true;
    state.referenceCount -= 1;
    if (state.referenceCount != 0) {
      return;
    }
    if (identical(state.leases[state.normalizedName], state)) {
      state.leases.remove(state.normalizedName);
    }
    if (state.ownsBox && box.isOpen) {
      await box.close();
    }
  }
}

void _validateBoxName(String boxName) {
  final isAscii = boxName.codeUnits.every((codeUnit) => codeUnit <= 0x7f);
  if (boxName.isEmpty || boxName.length > 255 || !isAscii) {
    throw ArgumentError.value(
      boxName.length,
      'boxName',
      'Must be non-empty ASCII with at most 255 code units.',
    );
  }
}
