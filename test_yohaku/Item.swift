//
//  Item.swift
//  test_yohaku
//
//  Created by mi on 2026/09/12.
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
