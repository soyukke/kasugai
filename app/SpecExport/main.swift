import Darwin
import Foundation

@main
struct KasugaiSpecExport {
    static func main() {
        let tables: [StateMachineTable] = [
            WebViewSyncMachine.table(),
            SyncLoopMachine.table(),
            MobileBridgeMachine.table(),
            FactoryRunMachine.table(),
        ]
        for table in tables {
            guard let json = table.toJSON() else {
                fputs("kasugai-spec-export: failed to encode state machine table\n", stderr)
                exit(EXIT_FAILURE)
            }
            print(json)
        }
    }
}
