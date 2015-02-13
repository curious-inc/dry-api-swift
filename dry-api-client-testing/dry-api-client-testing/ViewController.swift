//
//  ViewController.swift
//  dry-api-client-testing
//
//  Created by Kendrick Taylor on 2/11/15.
//  Copyright (c) 2015 Curious Inc. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    override func loadView() {
        self.view = UIView();
        let label = UILabel(frame: CGRectMake(0, 0, 100, 100)); 
        label.text = "Hello World.";
        self.view.addSubview(label);
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    func testClient(){



    }
}

