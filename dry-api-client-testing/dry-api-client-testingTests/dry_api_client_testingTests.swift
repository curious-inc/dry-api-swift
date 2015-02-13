//
//  dry_api_client_testingTests.swift
//  dry-api-client-testingTests
//
//  Created by Kendrick Taylor on 2/11/15.
//  Copyright (c) 2015 Curious Inc. All rights reserved.
//

import UIKit
import XCTest

/*
  XCTestExpectation *documentOpenExpectation = [self expectationWithDescription:@"document open"];
  async{
      assert(true);
     [documentOpenExpectation fulfill];
     }
[self waitForExpectationsWithTimeout:1 handler:^(NSError *error) {
        [doc closeWithCompletionHandler:nil];
    }];
    */

class dry_api_client_testingTests: XCTestCase {
    
    func asyncTest(method: ((done: ()->())->())) {
        var expectation = self.expectationWithDescription("async expectation");

        method({
            expectation.fulfill();
        });

        self.waitForExpectationsWithTimeout(2, handler:{ (error: NSError!) in
        });
    }

    func log(str: NSString){
        println("log: ");
        println("log: \(str)");
        println("log: ");
    }

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        // This is an example of a functional test case.
        XCTAssert(true, "Pass")
    }

    /*
    func testConnect(){

        var client = DryApiClient("http://localhost:9998/api");

        self.asyncTest({ (done) in
            client.postRequest("http://localhost:9998/api", "", { (error: DryApiError?, data: NSData?) in
                XCTAssert(true, "Called back")
                if let error = error {
                    self.log("ERROR: \(error)");

                }else if let data = data {
                    if let dataStr = NSString(data: data, encoding: NSUTF8StringEncoding) {
                        self.log("DATA: \(dataStr)");
                    }
                }
 
                done();
            });
        });
    }
    */

    func testCallGood(){
        var client = DryApiClient("");

        self.asyncTest({ (done) in
            client.callSimple("test", { (error: DryApiError?, data: String?) in

                XCTAssert(error == nil, "error is nil")
                XCTAssert(data != nil, "data is not nil")

                if let error = error {
                    self.log("ERROR: \(error)");
                }

                if(data != nil){
                    self.log("Data: \(data)");
                }
                done();
            });
        });
    }

    func testCallDoubleBad(){
        var client = DryApiClient("");

        self.asyncTest({ (done) in
            client.callSimple("test", { (error, data0: String?, data1: Int?) in


                if let error = error {
                    self.log("ERROR: \(error)");
                }


                if(error == nil){
                    self.log("data0: \(data0)");
                    self.log("data1: \(data1)");
                }

                XCTAssert(error != nil, "error is not nil")
                XCTAssert(data0 == nil, "data is nil")
                XCTAssert(data1 == nil, "data is nil")

                done();
            });
        });
    }

    func testCallDoubleGood(){
        var client = DryApiClient("");

        self.asyncTest({ (done) in
            client.callSimple("test", { (error, data0: String?, data1: String?) in


                if let error = error {
                    self.log("ERROR: \(error)");
                }

                if(error == nil){
                    self.log("data0: \(data0)");
                    self.log("data1: \(data1)");
                }

                XCTAssert(error == nil, "error is not nil")
                XCTAssert(data0 == "zero", "data is nil")
                XCTAssert(data1 == "one", "data is nil")

                done();
            });
        });
    }

    /*
    func testCallTripleGood(){
        var client = DryApiClient("");

        self.asyncTest({ (done) in
            client.callSimple("test", { (error: DryApiError?, data0: String?, data1: String?, data2: String?) in


                if let error = error {
                    self.log("ERROR: \(error)");
                }

                if(error == nil){
                    self.log("data0: \(data0)");
                    self.log("data1: \(data1)");
                    self.log("data2: \(data2)");
                }

                XCTAssert(error == nil, "error is not nil")
                XCTAssert(data0 != nil, "data0 is not nil")
                XCTAssert(data1 == nil, "data1 is nil")
                XCTAssert(data2 == nil, "data2 is nil")

                done();
            });
        });
    }

    */




    /*
    func testCall(){
        var client = DryApiClient("http://localhost:9998/api");
        // client.callTwoStrings();

        client.call("test", { (error: NSDictionary?, data: String?) in

            if let error = error {
                println("ERROR: \(error)");
                return
            }

            if(data != nil){
                println("Data: \(data)");
            }
        });

        client.call("test", { (error: NSDictionary?, data: Int?) in

            if let error = error {
                return println("ERROR: \(error)");
            }

            if(data != nil){
                println("Data: \(data)");
            }
        });
    }
    */
 
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measureBlock() {
            // Put the code you want to measure the time of here.
        }
    }
    
}
