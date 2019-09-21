//
//  MensaDatabase.swift
//  Mensa-Guthaben
//
//  Created by Georg on 16.09.19.
//  Copyright © 2019 Georg Sieber. All rights reserved.
//

import Foundation
import SQLite3

class MensaDatabase {
    
    static var DB_FILE = "mensa.sqlite"
    static var CREATE_DB_STATEMENTS = [
        "CREATE TABLE IF NOT EXISTS history (id INTEGER PRIMARY KEY AUTOINCREMENT, balance TEXT, lastTransaction TEXT, scanDate TEXT, cardID TEXT)"
    ]
    
    var db: OpaquePointer?
    
    init() {
        let fileurl = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent(MensaDatabase.DB_FILE)
        
        if(sqlite3_open(fileurl.path, &db) != SQLITE_OK) {
            print("error opening database "+fileurl.path)
        }
        for query in MensaDatabase.CREATE_DB_STATEMENTS {
            if(sqlite3_exec(db, query, nil,nil,nil) != SQLITE_OK) {
                print("error creating table: "+String(cString: sqlite3_errmsg(db)!))
            }
        }
    }
    
    func insertRecord(balance:Double, lastTransaction:Double, date:String, cardID: String) {
        var stmt:OpaquePointer?
        if sqlite3_prepare(self.db, "INSERT INTO history(balance, lastTransaction, scanDate, cardID) VALUES (?,?,?,?)", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, balance)
            sqlite3_bind_double(stmt, 2, lastTransaction)
            let date2 = date as NSString
            sqlite3_bind_text(stmt, 3, date2.utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, cardID, -1, nil)
            if sqlite3_step(stmt) == SQLITE_DONE {
                sqlite3_finalize(stmt)
            }
        }
    }
    
    func deleteRecord(id:Int) {
        var stmt:OpaquePointer?
        if sqlite3_prepare(self.db, "DELETE FROM history WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(id))
            if sqlite3_step(stmt) == SQLITE_DONE {
                sqlite3_finalize(stmt)
            }
        }
    }
    
    func getEntries() -> [HistoryItem] {
        var historyStore: [HistoryItem] = []
        var stmt:OpaquePointer?
        if sqlite3_prepare(db, "SELECT id, balance, lastTransaction, scanDate, cardID FROM history ORDER BY id DESC", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                historyStore.append(HistoryItem(
                    id: Int(sqlite3_column_int(stmt, 0)),
                    balance: sqlite3_column_double(stmt, 1),
                    lastTransaction: sqlite3_column_double(stmt, 2),
                    date: String(cString: sqlite3_column_text(stmt, 3)),
                    cardID: String(cString: sqlite3_column_text(stmt, 4))
                ))
            }
        }
        return historyStore
    }
    
}
