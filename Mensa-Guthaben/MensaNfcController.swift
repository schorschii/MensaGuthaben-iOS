//
//  MensaNfcController.swift
//  Mensa-Guthaben
//
//  Created by Schorschii on 27.04.23.
//  Copyright © 2023 Georg Sieber. All rights reserved.
//

import Foundation
import CoreNFC

class MensaNfcController {

    let session: NFCTagReaderSession
    let mainVc: MainViewController
    init(session: NFCTagReaderSession, mainViewControllerReference: MainViewController) {
        self.session = session
        self.mainVc = mainViewControllerReference
    }

    func communicate(tag: NFCTag) {
        session.connect(to: tag) { (error: Error?) in
            if(error != nil) {
                print("CONNECTION ERROR: "+error!.localizedDescription)
                self.session.invalidate(errorMessage: NSLocalizedString("Connection error: " , comment: "") + error!.localizedDescription)
                return
            }
            print("CONNECTED TO CARD")

            // read id based on card type
            var idData = Data()
            var idInt = 0
            if case let NFCTag.miFare(tag) = tag {
                print("CARD TYPE: mifare "+String(tag.mifareFamily.rawValue))
                idData = tag.identifier
                if(idData.count == 7) {
                    idData.append(UInt8(0))
                }
                idInt = idData.withUnsafeBytes {
                    $0.load(as: Int.self)
                }
            } else if case let NFCTag.iso7816(tag) = tag {
                print("CARD TYPE: iso7816")
                // todo: put id extraction into function
                idData = tag.identifier
                if(idData.count == 7) {
                    idData.append(UInt8(0))
                }
                idInt = idData.withUnsafeBytes {
                    $0.load(as: Int.self)
                }
            } else {
                print("INVALID CARD TYPE: " + String(describing:tag))
                self.session.invalidate(errorMessage: NSLocalizedString("Invalid card type: ", comment: "") + String(describing:tag))
                return
            }

            // display card ID
            print("CARD-ID hex: "+idData.hexEncodedString())
            DispatchQueue.main.async {
                self.mainVc.displayValues(
                    currentBalance: nil,
                    lastTransaction: nil,
                    cardId: String(idInt),
                    date: nil
                )
            }

            // 1st command : select app
            self.send(
                tag: tag,
                data: self.compileNfcRequest(
                    command: 0x5a, // command : select app
                    parameter: MainViewController.APP_ID.toByteArray()
                ),
                completion: { (data1) -> () in

                    // 2nd command : read value (balance)
                    self.send(
                        tag: tag,
                        data: self.compileNfcRequest(
                            command: 0x6c, // command : read value
                            parameter: [MainViewController.FILE_ID] // file id : 1
                        ),
                        completion: { (data2) -> () in

                            // parse and display balance response
                            var trimmedData = data2
                            trimmedData.removeLast()
                            trimmedData.removeLast()
                            trimmedData.reverse()
                            let currentBalanceRaw = [UInt8](trimmedData).toInt()
                            let currentBalanceValue : Double = self.intToEuro(value:currentBalanceRaw)
                            DispatchQueue.main.async {
                                self.mainVc.displayValues(
                                    currentBalance: currentBalanceValue,
                                    lastTransaction: nil,
                                    cardId: nil,
                                    date: nil
                                )
                            }

                            // 3rd command : read last transaction
                            self.send(
                                tag: tag,
                                data: self.compileNfcRequest(
                                    command: 0xf5, // command : get file settings
                                    parameter: [MainViewController.FILE_ID] // file id : 1
                                ),
                                completion: { (data3) -> () in

                                    // parse and display last transaction response
                                    var lastTransactionValue : Double = 0
                                    let buf = [UInt8](data3)
                                    if(buf.count > 13) {
                                        let lastTransactionRaw = [ buf[13], buf[12] ].toInt()
                                        lastTransactionValue = self.intToEuro(value:lastTransactionRaw)
                                        DispatchQueue.main.async {
                                            self.mainVc.displayValues(
                                                currentBalance: nil,
                                                lastTransaction: lastTransactionValue,
                                                cardId: nil,
                                                date: nil
                                            )
                                        }
                                    }

                                    // insert into history
                                    self.mainVc.db.insertRecord(
                                        balance: currentBalanceValue,
                                        lastTransaction: lastTransactionValue,
                                        cardID: String(idInt)
                                    )

                                    // dismiss iOS NFC window
                                    self.session.invalidate()

                                }
                            )

                        }
                    )

                }
            )

        }
    }
    func send(tag:NFCTag, data:Data, completion:@escaping (_ data: Data)->()) {
        print("COMMAND TO CARD => "+data.hexEncodedString())
        if case let NFCTag.miFare(tag) = tag {
            tag.sendMiFareCommand(commandPacket: data, completionHandler: { (data:Data, error:Error?) in
                if(error != nil) {
                    print("COMMAND ERROR: "+error!.localizedDescription)
                    return
                }
                print("CARD RESPONSE <= "+data.hexEncodedString())
                completion(data)
            })
        } else if case let NFCTag.iso7816(tag) = tag {
            tag.sendCommand(apdu: NFCISO7816APDU(data: data)!, completionHandler: { (data:Data, sw1: UInt8, sw2: UInt8, error:Error?) in
                if(error != nil) {
                    print("COMMAND ERROR: "+error!.localizedDescription)
                    return
                }
                print("CARD RESPONSE <= "+data.hexEncodedString())
                completion(data)
            })
        }
    }

    func compileNfcRequest(command: UInt8, parameter: [UInt8]?) -> Data {
        var buff : [UInt8] = []
        buff.append(0x90)
        buff.append(command)
        buff.append(0x00)
        buff.append(0x00)
        if(parameter != nil) {
            buff.append(UInt8(parameter!.count))
            for p in parameter! {
                buff.append(p)
            }
        }
        buff.append(0x00)
        return Data(buff)
    }

    func intToEuro(value:Int) -> Double {
        return (Double(value)/1000).rounded(toPlaces: 2)
    }

}

extension [UInt8] {
    func toInt() -> Int {
        var rawValue : Int = 0
        for byte in self {
            rawValue = rawValue << 8
            rawValue = rawValue | Int(byte)
        }
        return rawValue
    }
}

extension Int {
    func toByteArray() -> [UInt8] {
        var buf : [UInt8] = [];
        buf.append( UInt8((self & 0xFF0000) >> 16) )
        buf.append( UInt8((self & 0xFF00) >> 8) )
        buf.append(  UInt8(self & 0xFF) )
        return buf
    }
}

extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }
    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        return map { String(format: format, $0) }.joined()
    }
}

extension Double {
    // rounds the double to decimal places value
    func rounded(toPlaces places:Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
