/// Whether a network source currently considers requests worth attempting.
enum KacheNetworkState {
  /// No usable network path is currently known.
  unavailable,

  /// A network path is available, without guaranteeing Internet reachability.
  available,
}

/// Supplies network availability without coupling Kache to a platform plugin.
///
/// Each subscription to [states] must start with the source's current state,
/// followed by later changes. Implementations may report errors through the
/// stream; clients keep cached data and expose those errors as lifecycle events.
abstract interface class KacheNetwork {
  /// Current state followed by later availability changes.
  Stream<KacheNetworkState> get states;

  /// Releases resources owned by this source.
  ///
  /// This operation must be idempotent.
  Future<void> close();
}

/// Determines whether a client closes its network source.
enum KacheNetworkOwnership {
  /// The source is managed externally and must not be closed by the client.
  borrowed,

  /// The client owns and closes the source with its own lifecycle.
  owned,
}
