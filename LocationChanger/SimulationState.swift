import Foundation

// One source of truth for the simulation lifecycle.
enum SimulationState: Equatable {
    case idle
    case starting
    case running
    case stopping
    case cleanupRequired(String)
    case failed(String)

    // A new session is allowed only when no cleanup is pending.
    var canStart: Bool {
        switch self {
        case .idle, .failed:
            return true
        default:
            return false
        }
    }

    // Recovery stays available after an interrupted session.
    var canStop: Bool {
        switch self {
        case .running, .cleanupRequired:
            return true
        default:
            return false
        }
    }

    // Starting and stopping must finish before another action begins.
    var isBusy: Bool {
        switch self {
        case .starting, .stopping:
            return true
        default:
            return false
        }
    }

    var title: String {
        switch self {
        case .idle:
            return "Ready"
        case .starting:
            return "Starting…"
        case .running:
            return "Session launched"
        case .stopping:
            return "Stopping…"
        case .cleanupRequired:
            return "Cleanup required"
        case .failed:
            return "Couldn't start"
        }
    }
}
