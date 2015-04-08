//
//  dry_api_client_testingTests.swift
//  dry-api-client-testingTests
//
//  Created by Kendrick Taylor on 2/11/15.
//  Copyright (c) 2015 Curious Inc. All rights reserved.
//

import UIKit
import XCTest

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

    let apiUrl = "http://localhost:9998/api";

    func testServer(){

        var client = DryApiClient("http://localhost:9998/api");

        self.asyncTest({ (done) in
            client.postRequest(self.apiUrl, "", { (error: DryApiError?, data: NSData?) in
                XCTAssert(error == nil, "No error received")
                XCTAssert(data != nil, "Data received")

                // let dataStr = NSString(data: data!, encoding: NSUTF8StringEncoding) 
                // self.log("testServer (dataStr): \(dataStr)");

                done();
            });
        });
    }

    func testTagsMatch(){
        var client = DryApiClient(apiUrl);

        XCTAssert(client.tags().count == 0);
        XCTAssert(client.tags("no_val") == nil);
        XCTAssert(client.tags("key_one", "val_one").tags("key_one")! == "val_one");
        XCTAssert(client.tags("key_one")! == "val_one");
        client.tags("key_two", "val_two")

        self.asyncTest({ (done) in
            client.call("test.tags", [ "key_one": "val_one", "key_two": "val_two" ], { (error, matchesTags: Bool?) in

                XCTAssert(error == nil, "error is nil")
                XCTAssert(matchesTags! == true, "tags match")

                done();
            });
        });
    }

    func testNoTagsMatch(){
        var client = DryApiClient(apiUrl);

        XCTAssert(client.tags().count == 0);

        self.asyncTest({ (done) in
            client.call("test.tags", [ "key_one": "val_one" ], { (error, matchesTags: Bool?) in

                XCTAssert(error == nil, "error is nil")
                XCTAssert(matchesTags! == false, "tags don't match")

                done();
            });
        });
    }
 
    func testEcho_0_2(){
        var client = DryApiClient(apiUrl);

        self.asyncTest({ (done) in
            client.call("test.echo", { (error, data0: String?, data1: String?) in

                XCTAssert(error == nil, "error is nil")
                XCTAssert(data0 == nil, "data0 is nil")
                XCTAssert(data1 == nil, "data1 is nil")

                done();
            });
        });
    }
    
    func testEcho_2_2_String_Null(){
        var client = DryApiClient(apiUrl);

        self.asyncTest({ (done) in
            client.call("test.echo", "zero", client.null, { (error, data0: String?, data1: String?) in

                XCTAssert(error == nil, "error is nil")
                XCTAssert(data0 == "zero", "data0 is zero")
                XCTAssert(data1 == nil, "data1 is nil")

                done();
            });
        });
    }

    func testEcho_2_2_String_String(){
        var client = DryApiClient(apiUrl);

        self.asyncTest({ (done) in
            client.call("test.echo", "zero", "one", { (error, data0: String?, data1: String?) in

                XCTAssert(error == nil, "error is nil")
                XCTAssert(data0 == "zero", "data0 is zero")
                XCTAssert(data1 == "one", "data1 is one")

                done();
            });
        });
    }

    func testEcho_2_2_Int_Double(){
        var client = DryApiClient(apiUrl);

        self.asyncTest({ (done) in
            client.call("test.echo", 0, 10.21, { (error, data0: Int?, data1: Double?) in

                XCTAssert(error == nil, "error is nil")
                XCTAssert(data0 == 0, "data0 is 0")
                XCTAssert(data1 == 10.21, "data1 is 10.21")

                done();
            });
        });
    }

    func testEcho_2_2_Array_Dictionary(){
        var client = DryApiClient(apiUrl);

        var a = ["zero", "one"];
        var h = ["zero": 0, "one": 1];

        self.asyncTest({ (done) in
            client.call("test.echo", a, h, { (error, data0: NSArray?, data1: NSDictionary?) in

                XCTAssert(error == nil, "error is nil")
                XCTAssert(data0 == a, "data0 is \(a)")
                XCTAssert(data1 == h, "data1 is \(h)")

                done();
            });
        });
    }

    func testEcho_2_3(){
        var client = DryApiClient(apiUrl);

        self.asyncTest({ (done) in
            client.call("test.echo", "a", "b", { (error, a: String?, b: String?, c: String?) in
                XCTAssert(error == nil, "error is nil")
                XCTAssert(a == "a", "a == a")
                XCTAssert(b == "b", "b == b")
                XCTAssert(c == nil, "c == nil")
                done();
            });
        });
    }

    func testEcho_0_0(){
        var client = DryApiClient(apiUrl);

        self.asyncTest({ (done) in
            client.call("test.echo", { (error) in
                XCTAssert(error == nil, "error is nil")
                done();
            });
        });
    }

    func testEcho_0_1(){
        var client = DryApiClient(apiUrl);

        self.asyncTest({ (done) in
            client.call("test.echo", { (error, arg0: String?) in
                XCTAssert(error == nil, "error is nil")
                XCTAssert(arg0 == nil, "arg0 is nil")
                done();
            });
        });
    }
}
