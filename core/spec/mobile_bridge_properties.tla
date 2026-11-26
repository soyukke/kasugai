---- MODULE mobile_bridge_properties ----
EXTENDS mobile_bridge

AuthStates == {"Connecting", "ConnectedIdle", "SyncingClean", "SyncingStale", "Reconnecting"}

unauthorizedAlwaysRevokesAuthenticated ==
    (moved /\ previous \in AuthStates /\ event = "Unauthorized") =>
        (state = "AuthRevoked" /\ outcome = "ClearCredentialsAndStop")

revokedNeverAutoReconnects ==
    (moved /\ previous = "AuthRevoked"
        /\ event \in {"ReconnectTimerFired", "ConnectRequested", "StreamEventReceived"}) =>
        (state = "AuthRevoked" /\ outcome = "Noop")

staleSyncAlwaysRefetches ==
    (moved /\ previous = "SyncingStale" /\ event = "SnapshotSucceeded") =>
        (state = "SyncingClean" /\ outcome = "FetchSnapshot")

disconnectAlwaysUnpairs ==
    (moved /\ previous /= "Unpaired" /\ event = "DisconnectRequested") =>
        (state = "Unpaired" /\ outcome = "DisconnectAndClear")

fetchOnlyWhenAuthorized ==
    (moved /\ outcome = "FetchSnapshot") =>
        (previous \in {"ConnectedIdle", "SyncingStale"} /\ state = "SyncingClean")

noopNeverMutatesState ==
    (moved /\ outcome = "Noop") => state = previous

neverPaired ==
    ~(moved /\ previous = "Pairing" /\ outcome = "PersistAndConnect" /\ state = "Connecting")

neverConnected ==
    ~(moved /\ outcome = "MarkSynced" /\ state = "ConnectedIdle")

neverStaleRefetch ==
    ~(moved /\ previous = "SyncingStale" /\ outcome = "FetchSnapshot" /\ state = "SyncingClean")

neverRecoveredFromDrop ==
    ~(moved /\ previous = "Reconnecting" /\ outcome = "FetchSnapshotAndStream" /\ state = "Connecting")

neverRevoked ==
    ~(moved /\ outcome = "ClearCredentialsAndStop" /\ state = "AuthRevoked")
====
