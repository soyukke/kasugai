import Foundation

struct StateMachineMove: Encodable {
    let from: String
    let event: String
    let outcome: String
    let to: String
}

struct StateMachineTable: Encodable {
    let states: [String]
    let events: [String]
    let outcomes: [String]
    let start: String
    let ends: [String]
    let moves: [StateMachineMove]

    static func build<S, E, O>(
        start: S,
        ends: [S] = [],
        advance: (S, E) -> (state: S, outcome: O)
    ) -> StateMachineTable
    where
        S: CaseIterable & RawRepresentable, S.RawValue == String,
        E: CaseIterable & RawRepresentable, E.RawValue == String,
        O: CaseIterable & RawRepresentable, O.RawValue == String
    {
        var moves: [StateMachineMove] = []
        for state in S.allCases {
            for event in E.allCases {
                let step = advance(state, event)
                moves.append(
                    StateMachineMove(
                        from: state.rawValue,
                        event: event.rawValue,
                        outcome: step.outcome.rawValue,
                        to: step.state.rawValue
                    )
                )
            }
        }
        return StateMachineTable(
            states: S.allCases.map(\.rawValue),
            events: E.allCases.map(\.rawValue),
            outcomes: O.allCases.map(\.rawValue),
            start: start.rawValue,
            ends: ends.map(\.rawValue),
            moves: moves
        )
    }

    func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
