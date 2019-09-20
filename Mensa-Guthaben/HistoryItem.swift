//
//  File.swift
//  Mensa-Guthaben
//
//  Created by Georg on 16.08.19.
//  Copyright © 2019 Georg Sieber. All rights reserved.
//

import Foundation

class HistoryItem {
    var id : Int
    var balance : Double
    var lastTransaction : Double
    var date : String
    var cardID : String
    
    init(id:Int, balance:Double, lastTransaction:Double, date:String, cardID:String) {
        self.id = id
        self.balance = balance
        self.lastTransaction = lastTransaction
        self.date = date
        self.cardID = cardID
    }
}
