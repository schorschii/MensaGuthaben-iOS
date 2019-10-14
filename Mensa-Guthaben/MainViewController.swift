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
import GoogleMobileAds

class MainViewController: UIViewController, NFCTagReaderSessionDelegate, GADBannerViewDelegate {
    
    static var APP_ID  : Int    = 0x5F8415
    static var FILE_ID : UInt8  = 1
    static var DEMO    : Bool   = false
    
    var session: NFCTagReaderSession?
    var db = MensaDatabase()
    
    @IBOutlet weak var bottomStackView: UIStackView!
    var bannerView: GADBannerView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if(MainViewController.DEMO) {
            demo()
        } else {
            initAds()
        }
    }
    
    func initAds() {
        bannerView = GADBannerView(adSize: kGADAdSizeBanner)
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        bottomStackView.insertArrangedSubview(bannerView, at: 0)
        bottomStackView.addConstraints(
            [
             NSLayoutConstraint(item: bannerView!,
                              attribute: .centerX,
                              relatedBy: .equal,
                              toItem: bottomStackView,
                              attribute: .centerX,
                              multiplier: 1,
                              constant: 0)
          ])
        bannerView.adUnitID = "ca-app-pub-9874695726033794/3374012921"
        //bannerView.adUnitID = "ca-app-pub-3940256099942544/2934735716" // test
        bannerView.rootViewController = self
        bannerView.delegate = self
        bannerView.load(GADRequest())
    }
    
    @IBOutlet weak var labelCurrentBalance: UILabel!
    @IBOutlet weak var labelLastTransaction: UILabel!
    @IBOutlet weak var labelCardID: UILabel!
    @IBOutlet weak var labelDate: UILabel!
    @IBOutlet weak var viewCardBackground: UIView!
    
    @IBAction func onClick(_ sender: UIButton) {
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
                
                let idData = tag.identifier
                let idInt = idData.withUnsafeBytes {
                    $0.load(as: Int.self)
                }
                
                print("CONNECTED TO CARD")
                print("CARD-TYPE:"+String(tag.mifareFamily.rawValue))
                print("CARD-ID hex:"+idData.hexEncodedString())
                DispatchQueue.main.async {
                    self.labelCardID.text = String(idInt)
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
                                    self.labelCurrentBalance.text = String(format: "%.2f €", currentBalanceValue)
                                    self.labelDate.text = self.getDateString()
                                    UIView.animate(withDuration: 1.0, animations: {
                                        self.viewCardBackground.backgroundColor = self.getColorByEuro(euro:currentBalanceValue)
                                    })
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
                                                self.labelLastTransaction.text = String(format: "%.2f €", lastTransactionValue)
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
    func getColorByEuro(euro:Double) -> UIColor {
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
    
    func demo() {
        self.labelCurrentBalance.text = String(format: "%.2f €", 15.48)
        self.labelLastTransaction.text = String(format: "%.2f €", 5.98)
        self.labelDate.text = self.getDateString()
        self.labelCardID.text = "1234567890"
        UIView.animate(withDuration: 1.0, animations: {
            self.viewCardBackground.backgroundColor = self.getColorByEuro(euro:15.48)
        })
    }
    
    func getDateString() -> String {
        let dateFormatterGet = DateFormatter()
        dateFormatterGet.dateFormat = "dd.MM.yyyy HH:mm"
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
    
    // AD DELEGATE //
    
    /// Tells the delegate an ad request loaded an ad.
    func adViewDidReceiveAd(_ bannerView: GADBannerView) {
      print("adViewDidReceiveAd")
    }

    /// Tells the delegate an ad request failed.
    func adView(_ bannerView: GADBannerView,
        didFailToReceiveAdWithError error: GADRequestError) {
      print("adView:didFailToReceiveAdWithError: \(error.localizedDescription)")
    }

    /// Tells the delegate that a full-screen view will be presented in response
    /// to the user clicking on an ad.
    func adViewWillPresentScreen(_ bannerView: GADBannerView) {
      print("adViewWillPresentScreen")
    }

    /// Tells the delegate that the full-screen view will be dismissed.
    func adViewWillDismissScreen(_ bannerView: GADBannerView) {
      print("adViewWillDismissScreen")
    }

    /// Tells the delegate that the full-screen view has been dismissed.
    func adViewDidDismissScreen(_ bannerView: GADBannerView) {
      print("adViewDidDismissScreen")
    }

    /// Tells the delegate that a user click will open another app (such as
    /// the App Store), backgrounding the current app.
    func adViewWillLeaveApplication(_ bannerView: GADBannerView) {
      print("adViewWillLeaveApplication")
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
