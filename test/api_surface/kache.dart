import 'package:kache/kache.dart';

void verifyKacheTypes({
  required KacheClient client,
  required KacheResource<int> resource,
  required KacheKey key,
  required KacheNamespace namespace,
  required KacheKeyFormatException keyError,
  required KacheQuery<int> query,
  required KacheStorageMode storageMode,
  required KacheFetchContext fetchContext,
  required KachePolicy policy,
  required KacheRevalidation revalidation,
  required KacheFreshness freshness,
  required KacheSnapshot<int> snapshot,
  required KachePhase phase,
  required KacheDataSource source,
  required KachePersistencePhase persistencePhase,
  required KachePersistenceState persistenceState,
  required KachePersistenceBackend backend,
  required KachePersistenceBinding<int> binding,
  required KachePersistenceRead<int> read,
  required KachePersistedEntry<int> entry,
  required KachePersistedMetadata metadata,
  required KachePersistenceOwnership persistenceOwnership,
  required KachePersistenceOperation persistenceOperation,
  required KachePersistenceStage persistenceStage,
  required KachePersistenceException persistenceError,
  required KachePersistenceBindingException bindingError,
  required MemoryKachePersistence memoryBackend,
  required KacheFailure failure,
  required KacheFailureKind failureKind,
  required KacheFailureScope failureScope,
  required KacheConfigurationException configurationError,
  required KacheLifecycleException lifecycleError,
  required KacheCacheMissException cacheMiss,
  required KacheFetchUnavailableException fetchUnavailable,
  required KacheClearResult clearResult,
  required KacheCommandException commandError,
  required KacheEvent event,
  required KacheEventKind eventKind,
  required KacheCacheLayer cacheLayer,
  required KacheCancellationToken cancellation,
  required KacheCancellationController cancellationController,
  required KacheCancelledException cancellationError,
  required KacheScheduledTask scheduledTask,
}) {
  client.pausePolling();
  client.resumePolling();
  policy.refreshInterval;
  snapshot.isLoading;
  snapshot.isReady;
  snapshot.isFailed;
  snapshot.isStale;
  snapshot.hasFailure;
  event.layer;
}

KacheClock verifyClock(KacheClock clock) => clock;

KacheScheduler verifyScheduler(KacheScheduler scheduler) => scheduler;

KacheFetcher<int> verifyFetcher(KacheFetcher<int> fetcher) => fetcher;

KacheObserver verifyObserver(KacheObserver observer) => observer;

KachePersistenceMaintenance verifyMaintenance(
  KachePersistenceMaintenance maintenance,
) => maintenance;
