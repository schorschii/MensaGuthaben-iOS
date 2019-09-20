//
//  HistoryTableViewCell.swift
//  Mensa-Guthaben
//
//  Created by Georg on 16.08.19.
//  Copyright © 2019 Georg Sieber. All rights reserved.
//

import UIKit

class HistoryTableViewCell: UITableViewCell {

    @IBOutlet weak var labelBalance: UILabel!
    @IBOutlet weak var labelDate: UILabel!
    @IBOutlet weak var labelCardID: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }

}
