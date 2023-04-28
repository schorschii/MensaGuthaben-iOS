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
    
    static var DEMO : Bool   = false
    
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
                cardId: "1234567890",
                date: nil
            )
        } else {
            // restore last state
            let db = MensaDatabase()
            let historyItems = db.getEntries()
            if(!historyItems.isEmpty) {
                displayValues(
                    currentBalance: historyItems[0].balance,
                    lastTransaction: historyItems[0].lastTransaction,
                    cardId: historyItems[0].cardID,
                    date: historyItems[0].date
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
        let nfcController = MensaNfcController(session: session, mainViewControllerReference: self)
        for tag in tags {
            nfcController.communicate(tag: tag)
            return
        }
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
    
    func displayValues(currentBalance:Double?, lastTransaction:Double?, cardId:String?, date:String?) {
        if let currentBalanceUnwrapped = currentBalance {
            self.labelCurrentBalance.text = String(format: "%.2f €", currentBalanceUnwrapped)
            UIView.animate(withDuration: 1.0, animations: {
                self.viewCardBackground.backgroundColor = self.getColorByEuro(currentBalanceUnwrapped)
            })
        }
        if let lastTransactionUnwrapped = lastTransaction {
            self.labelLastTransaction.text = String(format: "%.2f €", lastTransactionUnwrapped)
        }
        if let cardIdUnwrapped = cardId {
            self.labelCardID.text = cardIdUnwrapped
        }
        if let dateUnwrapped = date {
            self.labelDate.text = dateUnwrapped
        } else {
            self.labelDate.text = MensaDatabase.getCurrentDateString()
        }
    }
    
}
