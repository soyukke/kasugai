---- MODULE provider_session_properties ----
EXTENDS provider_session

handshakeOrdering ==
    /\ ((moved /\ outcome = "SessionCreationStarted") =>
        (previous = "Initializing" /\ event = "InitializeOk" /\ state = "SessionCreating"))
    /\ ((moved /\ outcome = "SessionBecameReady") =>
        (previous = "SessionCreating" /\ event = "SessionReady" /\ state = "Ready"))

promptOnlyAfterReadyOrDirect ==
    /\ ((moved /\ outcome = "PromptDispatched") =>
        (previous = "Ready" /\ event = "SendPrompt" /\ state = "Prompting"))
    /\ ((moved /\ outcome = "DirectPromptStarted") =>
        (previous \in {"Disconnected", "Failed"} /\ event = "SpawnDirectPrompt" /\ state = "Prompting"))

deltaOnlyWhilePrompting ==
    (moved /\ outcome = "DeltaAccepted") =>
        (previous = "Prompting" /\ event = "ReceiveDelta" /\ state = "Prompting")

permissionOnlyWhilePrompting ==
    (moved /\ outcome = "PermissionPending") =>
        (previous = "Prompting" /\ event = "RequestPermission" /\ state = "AwaitingPermission")

permissionDecisionSound ==
    (moved /\ outcome \in {"PermissionAllowed", "PermissionDenied"}) =>
        (previous = "AwaitingPermission"
            /\ ((outcome = "PermissionAllowed" /\ state = "Prompting")
                \/ (outcome = "PermissionDenied" /\ state = "Ready")))

turnFinishOnlyWhilePrompting ==
    (moved /\ outcome = "TurnFinished") =>
        (previous = "Prompting" /\ event = "CompleteTurn" /\ state = "Ready")

noopNeverMutatesState ==
    (moved /\ outcome = "Noop") => state = previous

neverHandshakeCompleted ==
    ~(moved /\ outcome = "SessionBecameReady" /\ state = "Ready")

neverDirectPromptFinished ==
    ~(moved /\ outcome = "TurnFinished" /\ state = "Ready")

neverPermissionAllowed ==
    ~(moved /\ outcome = "PermissionAllowed" /\ state = "Prompting")

neverPermissionDenied ==
    ~(moved /\ outcome = "PermissionDenied" /\ state = "Ready")

neverRecoveredAfterFailure ==
    ~(moved /\ previous = "Failed" /\ outcome = "HandshakeStarted" /\ state = "Initializing")
====
