/// Supplies the current time to cache operations.
///
/// Inject a deterministic implementation in tests. Returned values may use
/// any time zone; Kache normalizes them to UTC before storing or comparing.
typedef KacheClock = DateTime Function();

/// Returns the current wall-clock time normalized to UTC.
DateTime systemKacheClock() => DateTime.now().toUtc();
