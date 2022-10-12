//
//  ViewController.swift
//  Mensa-Guthaben
//
//  Created by Georg on 11.08.19.
//  Copyright © 2019 Georg Sieber. All rights reserved.
//

import UIKit
import CoreNFC
import SQLite3

class MainViewController: UIViewController, NFCTagReaderSessionDelegate {
    
    static var APP_ID  : Int    = 0x5F8415
    static var FILE_ID : UInt8  = 1
    static var DEMO    : Bool   = false
    
    var session: NFCTagReaderSession?
    var db = MensaDatabase()
    
    @IBOutlet weak var bottomStackView: UIStackView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if(MainViewController.DEMO) {
            // show demo values for App Store screenshots
            displayValues(
                currentBalance: 15.48,
                lastTransaction: 5.98,
                date: self.getDateString(),
                cardId: "1234567890"
            )
        } else {
            // restore last state
            let db = MensaDatabase()
            let historyItems = db.getEntries()
            if(!historyItems.isEmpty) {
                displayValues(
                    currentBalance: historyItems[0].balance,
                    lastTransaction: historyItems[0].lastTransaction,
                    date: historyItems[0].date,
                    cardId: historyItems[0].cardID
                )
            }
        }
    }
    override func restoreUserActivityState(_ activity: NSUserActivity) {
        // app was started via shortcut, directly start scan process
        if #available(iOS 12.0, *) {
            if activity.interaction?.intent is ReadMensaCardIntent {
                startReaderSession()
            }
        }
    }
    
    @IBOutlet weak var labelCurrentBalance: UILabel!
    @IBOutlet weak var labelLastTransaction: UILabel!
    @IBOutlet weak var labelCardID: UILabel!
    @IBOutlet weak var labelDate: UILabel!
    @IBOutlet weak var viewCardBackground: UIView!
    
    @IBAction func onClick(_ sender: UIButton) {
        startReaderSession()
    }
    
    func startReaderSession() {
        guard NFCTagReaderSession.readingAvailable else {
            let alertController = UIAlertController(
                title: NSLocalizedString("NFC Not Supported", comment: ""),
                message: NSLocalizedString("This device doesn't support NFC tag scanning.", comment: ""),
                preferredStyle: .alert
            )
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alertController, animated: true, completion: nil)
            return
        }
        
        session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self)
        session?.alertMessage = NSLocalizedString("Please hold your Mensa card near the NFC sensor.", comment: "")
        session?.begin()
    }
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
    }
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        print(error.localizedDescription)
    }
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        if(tags.count != 1) {
            print("MULTIPLE TAGS! ABORT.")
            return
        }
        
        if case let NFCTag.miFare(tag) = tags.first! {
            
            session.connect(to: tags.first!) { (error: Error?) in
                if(error != nil) {
                    print("CONNECTION ERROR : "+error!.localizedDescription)
                    return
                }
                
                var idData = tag.identifier
                if(idData.count == 7) {
                    idData.append(UInt8(0))
                }
                let idInt = idData.withUnsafeBytes {
                    $0.load(as: Int.self)
                }
                
                print("CONNECTED TO CARD")
                print("CARD-TYPE:"+String(tag.mifareFamily.rawValue))
                print("CARD-ID hex:"+idData.hexEncodedString())
                DispatchQueue.main.async {
                    self.displayValues(
                        currentBalance: nil,
                        lastTransaction: nil,
                        date: nil,
                        cardId: String(idInt)
                    )
                }
                
                var appIdBuff : [Int] = [];
                appIdBuff.append ((MainViewController.APP_ID & 0xFF0000) >> 16)
                appIdBuff.append ((MainViewController.APP_ID & 0xFF00) >> 8)
                appIdBuff.append  (MainViewController.APP_ID & 0xFF)
                
                // 1st command : select app
                self.send(
                    tag: tag,
                    data: Data(_: self.wrap(
                        command: 0x5a, // command : select app
                        parameter: [UInt8(appIdBuff[0]), UInt8(appIdBuff[1]), UInt8(appIdBuff[2])] // appId as byte array
                    )),
                    completion: { (data1) -> () in
                        
                        // 2nd command : read value (balance)
                        self.send(
                            tag: tag,
                            data: Data(_: self.wrap(
                                command: 0x6c, // command : read value
                                parameter: [MainViewController.FILE_ID] // file id : 1
                            )),
                            completion: { (data2) -> () in
                                
                                // parse balance response
                                var trimmedData = data2
                                trimmedData.removeLast()
                                trimmedData.removeLast()
                                trimmedData.reverse()
                                let currentBalanceRaw = self.byteArrayToInt(
                                    buf: [UInt8](trimmedData)
                                )
                                let currentBalanceValue : Double = self.intToEuro(value:currentBalanceRaw)
                                DispatchQueue.main.async {
                                    self.displayValues(
                                        currentBalance: currentBalanceValue,
                                        lastTransaction: nil,
                                        date: self.getDateString(),
                                        cardId: nil
                                    )
                                }
                                
                                // 3rd command : read last trans
                                self.send(
                                    tag: tag,
                                    data: Data(_: self.wrap(
                                        command: 0xf5, // command : get file settings
                                        parameter: [MainViewController.FILE_ID] // file id : 1
                                    )),
                                    completion: { (data3) -> () in
                                        
                                        // parse last transaction response
                                        var lastTransactionValue : Double = 0
                                        let buf = [UInt8](data3)
                                        if(buf.count > 13) {
                                            let lastTransactionRaw = self.byteArrayToInt(
                                                buf:[ buf[13], buf[12] ]
                                            )
                                            lastTransactionValue = self.intToEuro(value:lastTransactionRaw)
                                            DispatchQueue.main.async {
                                                self.displayValues(
                                                    currentBalance: nil,
                                                    lastTransaction: lastTransactionValue,
                                                    date: nil,
                                                    cardId: nil
                                                )
                                            }
                                        }
                                        
                                        // insert into history
                                        self.db.insertRecord(
                                            balance: currentBalanceValue,
                                            lastTransaction: lastTransactionValue,
                                            date: self.getDateString(),
                                            cardID: String(idInt)
                                        )
                                        
                                        // dismiss iOS NFC window
                                        session.invalidate()
                                        
                                    }
                                )
                                
                            }
                        )
                        
                    }
                )
                
            }
            
        } else {
            print("INVALID CARD")
        }
    }
    
    func byteArrayToInt(buf:[UInt8]) -> Int {
        var rawValue : Int = 0
        for byte in buf {
            rawValue = rawValue << 8
            rawValue = rawValue | Int(byte)
        }
        return rawValue
    }
    func intToEuro(value:Int) -> Double {
        return (Double(value)/1000).rounded(toPlaces: 2)
    }
    func getColorByEuro(_ euro:Double) -> UIColor {
        let maxEuro = 10.0
        var position = CGFloat(euro/maxEuro)
        if(position > 1) {position = 1}
        if(position < 0) {position = 0}
        
        let colorGreenR = CGFloat(38)/255
        let colorGreenG = CGFloat(152)/255
        let colorGreenB = CGFloat(88)/255
        
        let colorRedR = CGFloat(180)/255
        let colorRedG = CGFloat(15)/255
        let colorRedB = CGFloat(15)/255
        
        let colorR = colorRedR + position * (colorGreenR - colorRedR)
        let colorG = colorRedG + position * (colorGreenG - colorRedG)
        let colorB = colorRedB + position * (colorGreenB - colorRedB)
        
        return UIColor(
            red: colorR,
            green: colorG,
            blue: colorB,
            alpha: CGFloat(1)
        )
    }
    
    func displayValues(currentBalance:Double?, lastTransaction:Double?, date:String?, cardId:String?) {
        if let currentBalanceUnwrapped = currentBalance {
            self.labelCurrentBalance.text = String(format: "%.2f €", currentBalanceUnwrapped)
            UIView.animate(withDuration: 1.0, animations: {
                self.viewCardBackground.backgroundColor = self.getColorByEuro(currentBalanceUnwrapped)
            })
        }
        if let lastTransactionUnwrapped = lastTransaction {
            self.labelLastTransaction.text = String(format: "%.2f €", lastTransactionUnwrapped)
        }
        if let dateUnwrapped = date {
            self.labelDate.text = dateUnwrapped
        }
        if let cardIdUnwrapped = cardId {
            self.labelCardID.text = cardIdUnwrapped
        }
    }
    
    func getDateString() -> String {
        let dateFormatterGet = DateFormatter()
        dateFormatterGet.dateFormat = "dd.MM. HH:mm"
        return dateFormatterGet.string(from: Date())
    }
    
    func wrap(command: UInt8, parameter: [UInt8]?) -> [UInt8] {
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
        return buff
    }
    func send(tag:NFCMiFareTag, data:Data, completion: @escaping (_ data: Data)->()) {
        print("COMMAND TO CARD => "+data.hexEncodedString())
        tag.sendMiFareCommand(commandPacket: data, completionHandler: { (data:Data, error:Error?) in
            if(error != nil) {
                print("COMMAND ERROR : "+error!.localizedDescription)
                return
            }
            print("CARD RESPONSE <= "+data.hexEncodedString())
            completion(data)
        })
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
    // Rounds the double to decimal places value
    func rounded(toPlaces places:Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
