//
//  MiningMode.swift
//  iOSMiner
//
//  Created by Cooper Wang on 4/3/2026.
//

import Foundation

/// Mining intensity modes.
/// - full: All available threads, maximum hashrate
/// - eco: Half the available threads, balanced power/performance
/// - tiny: Single thread, minimal battery/thermal impact
enum MiningMode: String, CaseIterable, Identifiable, Sendable {
    case full
    case eco
    case tiny

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .full: return "Full"
        case .eco:  return "Eco"
        case .tiny: return "Tiny"
        }
    }

    var description: String {
        switch self {
        case .full: return "All cores, max hashrate"
        case .eco:  return "Half cores, balanced"
        case .tiny: return "1 thread, minimal impact"
        }
    }

    var icon: String {
        switch self {
        case .full: return "flame.fill"
        case .eco:  return "leaf.fill"
        case .tiny: return "ant.fill"
        }
    }

    /// Compute the default thread count for this mode.
    func defaultThreadCount(maxThreads: Int) -> Int {
        switch self {
        case .full: return max(1, maxThreads)
        case .eco:  return max(1, maxThreads / 2)
        case .tiny: return 1
        }
    }
}
