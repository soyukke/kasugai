import Foundation

enum MobileBridgeState: String, CaseIterable {
    case unpaired = "Unpaired"
    case pairing = "Pairing"
    case connecting = "Connecting"
    case connectedIdle = "ConnectedIdle"
    case syncingClean = "SyncingClean"
    case syncingStale = "SyncingStale"
    case reconnecting = "Reconnecting"
    case authRevoked = "AuthRevoked"
}

enum MobileBridgeEvent: String, CaseIterable {
    case startPairing = "StartPairing"
    case pairingSucceeded = "PairingSucceeded"
    case pairingFailed = "PairingFailed"
    case connectRequested = "ConnectRequested"
    case snapshotSucceeded = "SnapshotSucceeded"
    case snapshotFailed = "SnapshotFailed"
    case streamEventReceived = "StreamEventReceived"
    case streamDisconnected = "StreamDisconnected"
    case unauthorized = "Unauthorized"
    case reconnectTimerFired = "ReconnectTimerFired"
    case disconnectRequested = "DisconnectRequested"
}

enum MobileBridgeOutcome: String, CaseIterable {
    case noop = "Noop"
    case submitPairing = "SubmitPairing"
    case persistAndConnect = "PersistAndConnect"
    case failPairing = "FailPairing"
    case fetchSnapshotAndStream = "FetchSnapshotAndStream"
    case fetchSnapshot = "FetchSnapshot"
    case markSynced = "MarkSynced"
    case bufferRefresh = "BufferRefresh"
    case scheduleReconnect = "ScheduleReconnect"
    case clearCredentialsAndStop = "ClearCredentialsAndStop"
    case disconnectAndClear = "DisconnectAndClear"
}

enum MobileBridgeMachine {
    static func advance(_ state: MobileBridgeState, _ event: MobileBridgeEvent) -> (
        state: MobileBridgeState, outcome: MobileBridgeOutcome
    ) {
        switch state {
        case .unpaired:
            switch event {
            case .startPairing:
                return (.pairing, .submitPairing)
            case .connectRequested:
                return (.connecting, .fetchSnapshotAndStream)
            case .pairingSucceeded, .pairingFailed, .snapshotSucceeded, .snapshotFailed,
                .streamEventReceived, .streamDisconnected, .unauthorized, .reconnectTimerFired,
                .disconnectRequested:
                return (.unpaired, .noop)
            }

        case .pairing:
            switch event {
            case .pairingSucceeded:
                return (.connecting, .persistAndConnect)
            case .pairingFailed, .unauthorized:
                return (.unpaired, .failPairing)
            case .disconnectRequested:
                return (.unpaired, .disconnectAndClear)
            case .startPairing, .connectRequested, .snapshotSucceeded, .snapshotFailed,
                .streamEventReceived, .streamDisconnected, .reconnectTimerFired:
                return (.pairing, .noop)
            }

        case .connecting:
            switch event {
            case .snapshotSucceeded:
                return (.connectedIdle, .markSynced)
            case .snapshotFailed, .streamDisconnected:
                return (.reconnecting, .scheduleReconnect)
            case .streamEventReceived:
                return (.syncingStale, .bufferRefresh)
            case .unauthorized:
                return (.authRevoked, .clearCredentialsAndStop)
            case .disconnectRequested:
                return (.unpaired, .disconnectAndClear)
            case .startPairing, .pairingSucceeded, .pairingFailed, .connectRequested,
                .reconnectTimerFired:
                return (.connecting, .noop)
            }

        case .connectedIdle:
            switch event {
            case .streamEventReceived, .connectRequested:
                return (.syncingClean, .fetchSnapshot)
            case .streamDisconnected:
                return (.reconnecting, .scheduleReconnect)
            case .unauthorized:
                return (.authRevoked, .clearCredentialsAndStop)
            case .disconnectRequested:
                return (.unpaired, .disconnectAndClear)
            case .startPairing, .pairingSucceeded, .pairingFailed, .snapshotSucceeded,
                .snapshotFailed, .reconnectTimerFired:
                return (.connectedIdle, .noop)
            }

        case .syncingClean:
            switch event {
            case .streamEventReceived, .connectRequested:
                return (.syncingStale, .bufferRefresh)
            case .snapshotSucceeded:
                return (.connectedIdle, .markSynced)
            case .snapshotFailed, .streamDisconnected:
                return (.reconnecting, .scheduleReconnect)
            case .unauthorized:
                return (.authRevoked, .clearCredentialsAndStop)
            case .disconnectRequested:
                return (.unpaired, .disconnectAndClear)
            case .startPairing, .pairingSucceeded, .pairingFailed, .reconnectTimerFired:
                return (.syncingClean, .noop)
            }

        case .syncingStale:
            switch event {
            case .streamEventReceived, .connectRequested:
                return (.syncingStale, .bufferRefresh)
            case .snapshotSucceeded:
                return (.syncingClean, .fetchSnapshot)
            case .snapshotFailed, .streamDisconnected:
                return (.reconnecting, .scheduleReconnect)
            case .unauthorized:
                return (.authRevoked, .clearCredentialsAndStop)
            case .disconnectRequested:
                return (.unpaired, .disconnectAndClear)
            case .startPairing, .pairingSucceeded, .pairingFailed, .reconnectTimerFired:
                return (.syncingStale, .noop)
            }

        case .reconnecting:
            switch event {
            case .reconnectTimerFired, .connectRequested:
                return (.connecting, .fetchSnapshotAndStream)
            case .unauthorized:
                return (.authRevoked, .clearCredentialsAndStop)
            case .disconnectRequested:
                return (.unpaired, .disconnectAndClear)
            case .startPairing, .pairingSucceeded, .pairingFailed, .snapshotSucceeded,
                .snapshotFailed, .streamEventReceived, .streamDisconnected:
                return (.reconnecting, .noop)
            }

        case .authRevoked:
            switch event {
            case .startPairing:
                return (.pairing, .submitPairing)
            case .disconnectRequested:
                return (.unpaired, .disconnectAndClear)
            case .pairingSucceeded, .pairingFailed, .connectRequested, .snapshotSucceeded,
                .snapshotFailed, .streamEventReceived, .streamDisconnected, .unauthorized,
                .reconnectTimerFired:
                return (.authRevoked, .noop)
            }
        }
    }

    static func table() -> StateMachineTable {
        StateMachineTable.build(
            start: MobileBridgeState.unpaired,
            ends: [],
            advance: advance
        )
    }

    static func runSelfTests() -> Bool {
        let s1 = advance(.unpaired, .startPairing)
        let s2 = advance(s1.state, .pairingSucceeded)
        let s3 = advance(s2.state, .snapshotSucceeded)
        let s4 = advance(s3.state, .streamEventReceived)
        let s5 = advance(s4.state, .streamEventReceived)
        let s6 = advance(s5.state, .snapshotSucceeded)
        let s7 = advance(s6.state, .streamDisconnected)
        let s8 = advance(s7.state, .reconnectTimerFired)
        let s9 = advance(s8.state, .unauthorized)
        let s10 = advance(s9.state, .reconnectTimerFired)
        let s11 = advance(s9.state, .disconnectRequested)
        return s1.state == .pairing
            && s1.outcome == .submitPairing
            && s2.state == .connecting
            && s2.outcome == .persistAndConnect
            && s3.state == .connectedIdle
            && s3.outcome == .markSynced
            && s4.state == .syncingClean
            && s4.outcome == .fetchSnapshot
            && s5.state == .syncingStale
            && s5.outcome == .bufferRefresh
            && s6.state == .syncingClean
            && s6.outcome == .fetchSnapshot
            && s7.state == .reconnecting
            && s7.outcome == .scheduleReconnect
            && s8.state == .connecting
            && s8.outcome == .fetchSnapshotAndStream
            && s9.state == .authRevoked
            && s9.outcome == .clearCredentialsAndStop
            && s10.state == .authRevoked
            && s10.outcome == .noop
            && s11.state == .unpaired
            && s11.outcome == .disconnectAndClear
    }
}
