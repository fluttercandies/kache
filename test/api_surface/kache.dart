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
  required KacheEventPhase eventPhase,
  required KacheEventTrigger eventTrigger,
  required KacheLayer layer,
  required KacheLookupResult lookup,
  required KacheCancelReason cancelReason,
  required KacheCancellationToken cancellation,
  required KacheCancellationController cancellationController,
  required KacheCancelledException cancellationError,
  required KacheScheduledTask scheduledTask,
  required KacheNetwork network,
  required KacheNetworkState networkState,
  required KacheNetworkOwnership networkOwnership,
}) {
  client.pausePolling();
  client.resumePolling();
  client.pauseReconnect();
  client.resumeReconnect();
  client.revalidateOnReconnect();
  client.cancel(key);
  client.cancelAll();
  client.networkState;
  policy.refreshInterval;
  policy.refreshOnReconnect;
  snapshot.isLoading;
  snapshot.isReady;
  snapshot.isFailed;
  snapshot.isStale;
  snapshot.hasFailure;
  event.layer;
  event.clientId;
  event.sequence;
  event.traceId;
  event.id;
  event.parentId;
  event.kind;
  event.phase;
  event.trigger;
  event.occurredAt;
  event.duration;
  event.key;
  event.namespace;
  event.debugName;
  event.metadata;
  event.lookup;
  event.networkState;
  event.failure;
  event.cancelReason;
  event.revision;
  event.hasData;
  event.dataOrNull;
  event.requireData<int>();
  event.scope;
  event.isTerminal;
  resource.cancel();
  cancellation.isCancelled;
  cancellation.reason;
  cancellation.whenCancelled;
  cancellationController.token;
  cancellationController.cancel();
  cancellationError.reason;
}

KacheClock verifyClock(KacheClock clock) => clock;

KacheScheduler verifyScheduler(KacheScheduler scheduler) => scheduler;

KacheFetcher<int> verifyFetcher(KacheFetcher<int> fetcher) => fetcher;

KacheObserver verifyObserver(KacheObserver observer) => observer;

KachePersistenceMaintenance verifyMaintenance(
  KachePersistenceMaintenance maintenance,
) => maintenance;

Future<KacheSnapshot<int>> verifyResourceRefresh(KacheResource<int> resource) =>
    resource.refresh();
