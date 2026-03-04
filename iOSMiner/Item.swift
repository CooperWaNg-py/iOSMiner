//
//  Item.swift
//  iOSMiner
//
//  Created by Cooper Wang on 4/3/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
