//
//  AboutViewController.swift
//  Mensa-Guthaben
//
//  Created by Georg on 15.08.19.
//  Copyright © 2019 Georg Sieber. All rights reserved.
//

import UIKit
import StoreKit

class AboutViewController: UIViewController, SKStoreProductViewControllerDelegate {
    
    @IBOutlet weak var labelVersion: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        labelVersion.text = "v"+(appVersion ?? "?")
    }
    
    @IBAction func onClickDone(_ sender: UIBarButtonItem) {
        dismiss(animated: true, completion: nil)
    }
    @IBAction func onClickWebsite(_ sender: UIButton) {
        if let url = URL(string: "https://georg-sieber.de") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    @IBAction func onClickEmail(_ sender: UIButton) {
        if let url = URL(string: "mailto:ios@georg-sieber.de") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    @IBAction func onClickGithub(_ sender: UIButton) {
        if let url = URL(string: "https://github.com/schorschii/MensaGuthaben-iOS") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    @IBAction func onClickShare(_ sender: UIButton) {
        // set up activity view controller
        let content = [
            "https://apps.apple.com/us/app/mensa-guthaben/id1476859721" +
            "\n\n" +
            NSLocalizedString("With this app you can scan your mensa card to get it's balance instantly! Get it now: Search for 'Mensa Balance' on the App Store!", comment: "")
        ]
        let activityViewController = UIActivityViewController(activityItems: content, applicationActivities: nil)
        activityViewController.popoverPresentationController?.sourceView = self.view // so that iPads won't crash

        // present the view controller
        self.present(activityViewController, animated: true, completion: nil)
    }
    @IBAction func onClickBallBreak(_ sender: Any) {
        openStoreProductWithiTunesItemIdentifier(identifier: "1409746305");
    }
    @IBAction func onClickItinventory(_ sender: UIButton) {
        openStoreProductWithiTunesItemIdentifier(identifier: "1442661035");
    }
    
    func openStoreProductWithiTunesItemIdentifier(identifier: String) {
        let storeViewController = SKStoreProductViewController()
        storeViewController.delegate = self

        let parameters = [ SKStoreProductParameterITunesItemIdentifier : identifier]
        storeViewController.loadProduct(withParameters: parameters) { [weak self] (loaded, error) -> Void in
            if loaded {
                // Parent class of self is UIViewContorller
                self?.present(storeViewController, animated: true, completion: nil)
            }
        }
    }
    func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
        dismiss(animated: true, completion: nil)
    }
    
}
