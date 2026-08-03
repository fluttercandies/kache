part of 'store.dart';

final Expando<Map<String, _HiveBoxLeaseState>> _hiveBoxLeases =
    Expando<Map<String, _HiveBoxLeaseState>>('kache_hive_box_leases');

typedef _CipherIdentity = ({Type cipherType, int keyCrc});

_CipherIdentity? _cipherIdentityOf(HiveCipher? cipher) {
  if (cipher == null) {
    return null;
  }
  try {
    return (
      cipherType: cipher.runtimeType,
      keyCrc: cipher.calculateKeyCrc(),
    );
  } on Object catch (error, stackTrace) {
    throw HiveCeOpenException._(error, stackTrace);
  }
}

Uint8List? _bytesDescriptorOf(Uint8List? bytes) {
  if (bytes == null) {
    return null;
  }
  return Uint8List.fromList(sha256.convert(bytes).bytes);
}

bool _digestsEqual(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _bytesDescriptorMatches(Uint8List? candidate, Uint8List? descriptor) {
  if (descriptor == null) {
    return candidate == null;
  }
  if (candidate == null) {
    return false;
  }
  return _digestsEqual(sha256.convert(candidate).bytes, descriptor);
}

Never _failOpen(String reason) =>
    throw HiveCeOpenException._(StateError(reason), StackTrace.current);

void _rejectBorrowedConfig({
  required String? path,
  required Uint8List? bytes,
  required bool crashRecovery,
  required HiveCipher? cipher,
}) {
  if (path != null) {
    _failOpen('Cannot specify a path for a box opened outside Kache.');
  }
  if (bytes != null) {
    _failOpen('Cannot specify bytes for a box opened outside Kache.');
  }
  if (!crashRecovery) {
    _failOpen(
      'Cannot disable crash recovery for a box opened outside Kache.',
    );
  }
  if (cipher != null) {
    _failOpen(
      'Cannot verify the cipher for a box opened outside Kache.',
    );
  }
}

Future<_HiveBoxLeaseHandle> _acquireHiveBox({
  required HiveInterface hive,
  required String boxName,
  required HiveCipher? encryptionCipher,
  required String keyStrategyIdentity,
  required bool crashRecovery,
  required String? path,
  required Uint8List? bytes,
}) async {
  _validateBoxName(boxName);
  if (path != null && bytes != null) {
    throw ArgumentError(
      'Cannot specify both path and bytes for a Hive box.',
      'path',
    );
  }

  final normalizedName = boxName.toLowerCase();
  final leases = _hiveBoxLeases[hive] ??= <String, _HiveBoxLeaseState>{};
  final closingState = leases[normalizedName];
  final closing = closingState?.closeFuture;
  if (closing != null) {
    try {
      await closing;
    } on Object catch (error, stackTrace) {
      throw HiveCeOpenException._(error, stackTrace);
    }
    return _acquireHiveBox(
      hive: hive,
      boxName: boxName,
      encryptionCipher: encryptionCipher,
      keyStrategyIdentity: keyStrategyIdentity,
      crashRecovery: crashRecovery,
      path: path,
      bytes: bytes,
    );
  }
  var state = closingState;

  if (state == null) {
    final wasOpen = hive.isBoxOpen(normalizedName);

    if (wasOpen) {
      _rejectBorrowedConfig(
        path: path,
        bytes: bytes,
        crashRecovery: crashRecovery,
        cipher: encryptionCipher,
      );
    }

    // Compute cipher identity before any openBox call so a throwing
    // calculateKeyCrc cannot leave an orphaned box open.
    final cipherIdentity = _cipherIdentityOf(encryptionCipher);

    late final Future<Box<Object?>> boxFuture;
    try {
      boxFuture = wasOpen
          ? Future<Box<Object?>>.value(hive.box<Object?>(normalizedName))
          : hive.openBox<Object?>(
              normalizedName,
              encryptionCipher: encryptionCipher,
              crashRecovery: crashRecovery,
              path: path,
              bytes: bytes,
            );
    } on Object catch (error, stackTrace) {
      throw HiveCeOpenException._(error, stackTrace);
    }

    state = _HiveBoxLeaseState(
      boxFuture: boxFuture,
      ownsBox: !wasOpen,
      leases: leases,
      normalizedName: normalizedName,
      cipher: encryptionCipher,
      cipherIdentity: cipherIdentity,
      keyStrategyIdentity: keyStrategyIdentity,
      path: path,
      bytesDescriptor: _bytesDescriptorOf(bytes),
      crashRecovery: crashRecovery,
    );
    leases[normalizedName] = state;
  } else {
    if (keyStrategyIdentity != state.keyStrategyIdentity) {
      _failOpen('Key strategy does not match the active lease.');
    }
    if (state.ownsBox) {
      if (path != state.path) {
        _failOpen('Path does not match the active lease.');
      }
      if (!_bytesDescriptorMatches(bytes, state.bytesDescriptor)) {
        _failOpen('Bytes configuration does not match the active lease.');
      }
      if (crashRecovery != state.crashRecovery) {
        _failOpen(
          'Crash recovery setting does not match the active lease.',
        );
      }
      if (!identical(encryptionCipher, state.cipher)) {
        _failOpen('Cipher object does not match the active lease.');
      }
      final currentCipherIdentity = _cipherIdentityOf(encryptionCipher);
      if (currentCipherIdentity != state.cipherIdentity) {
        _failOpen('Cipher identity does not match the active lease.');
      }
    } else {
      _rejectBorrowedConfig(
        path: path,
        bytes: bytes,
        crashRecovery: crashRecovery,
        cipher: encryptionCipher,
      );
    }
  }

  state.referenceCount += 1;
  late final Box<Object?> box;
  try {
    box = await state.boxFuture;
  } on Object catch (error, stackTrace) {
    state.referenceCount -= 1;
    if (identical(leases[normalizedName], state)) {
      leases.remove(normalizedName);
    }
    throw HiveCeOpenException._(error, stackTrace);
  }
  return _HiveBoxLeaseHandle(state: state, box: box);
}

final class _HiveBoxLeaseState {
  _HiveBoxLeaseState({
    required this.boxFuture,
    required this.ownsBox,
    required this.leases,
    required this.normalizedName,
    required this.cipher,
    required this.cipherIdentity,
    required this.keyStrategyIdentity,
    required this.path,
    required this.bytesDescriptor,
    required this.crashRecovery,
  });

  final Future<Box<Object?>> boxFuture;
  final bool ownsBox;
  final Map<String, _HiveBoxLeaseState> leases;
  final String normalizedName;
  final HiveCipher? cipher;
  final _CipherIdentity? cipherIdentity;
  final String keyStrategyIdentity;
  final String? path;
  final Uint8List? bytesDescriptor;
  final bool crashRecovery;
  int referenceCount = 0;
  Future<void>? closeFuture;
}

final class _HiveBoxLeaseHandle {
  _HiveBoxLeaseHandle({required this.state, required this.box});

  final _HiveBoxLeaseState state;
  final Box<Object?> box;
  bool _isReleased = false;

  bool get isOwned => state.ownsBox;

  Future<void> release() {
    if (_isReleased) {
      return Future<void>.value();
    }
    _isReleased = true;
    state.referenceCount -= 1;
    if (state.referenceCount != 0) {
      return Future<void>.value();
    }
    final future = _closeFinalLease();
    state.closeFuture = future;
    return future;
  }

  Future<void> _closeFinalLease() async {
    try {
      if (state.ownsBox && box.isOpen) {
        await box.close();
      }
    } finally {
      if (identical(state.leases[state.normalizedName], state)) {
        state.leases.remove(state.normalizedName);
      }
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
