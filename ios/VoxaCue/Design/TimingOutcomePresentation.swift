import SwiftUI
import VoxaCore

struct TimingOutcomePresentation {
    let title: String
    let aggregateLabel: String
    let metricDetail: String
    let symbol: String
    let tint: Color
}

extension TimingOutcome {
    var presentation: TimingOutcomePresentation {
        switch self {
        case .partial:
            TimingOutcomePresentation(
                title: "Partial session",
                aggregateLabel: "Partial",
                metricDetail: "short of target",
                symbol: "pause.circle",
                tint: CueTheme.secondaryInk
            )
        case .onTarget:
            TimingOutcomePresentation(
                title: "Finished on target",
                aggregateLabel: "On target",
                metricDetail: "from target",
                symbol: "checkmark",
                tint: CueTheme.green
            )
        case .overTarget:
            TimingOutcomePresentation(
                title: "Over target time",
                aggregateLabel: "Over target",
                metricDetail: "over target",
                symbol: "timer",
                tint: CueTheme.amber
            )
        }
    }
}
