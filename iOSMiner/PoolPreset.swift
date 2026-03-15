//
//  PoolPreset.swift
//  iOSMiner
//
//  Pre-configured mining pool definitions for easy switching.
//

import Foundation

struct PoolPreset: Identifiable, Hashable {
    let id: String          // unique key, e.g. "hmpool"
    let name: String        // display name
    let host: String
    let port: UInt16
    let description: String // short note
    let url: String         // website URL for reference

    /// All built-in pool presets
    static let builtIn: [PoolPreset] = [
        PoolPreset(
            id: "hmpool",
            name: "HMPool",
            host: "hmpool.io",
            port: 3337,
            description: "Solo mining pool, low diff",
            url: "https://hmpool.io"
        ),
        PoolPreset(
            id: "solo_ckpool",
            name: "Solo CKPool",
            host: "solo.ckpool.org",
            port: 3333,
            description: "Solo mining, lottery style",
            url: "https://solo.ckpool.org"
        ),
        PoolPreset(
            id: "ckpool",
            name: "CKPool",
            host: "pool.ckpool.org",
            port: 3333,
            description: "Pooled mining, PPLNS payout",
            url: "https://ckpool.org"
        ),
        PoolPreset(
            id: "braiins",
            name: "Braiins Pool",
            host: "stratum.braiins.com",
            port: 3333,
            description: "Major pool, FPPS payout",
            url: "https://braiins.com/pool"
        ),
        PoolPreset(
            id: "kano",
            name: "Kano Pool",
            host: "stratum.kano.is",
            port: 3333,
            description: "Small community pool",
            url: "https://kano.is"
        ),
        PoolPreset(
            id: "custom",
            name: "Custom",
            host: "",
            port: 3333,
            description: "Enter your own pool details",
            url: ""
        ),
    ]
}
