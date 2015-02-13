
import Foundation;

public class DryApiError {

    public let code: String;
    public let message: String;

    init(_ code: String, _ message: String){
        self.code = code;
        self.message = message;
    }

    init(_ error: NSError){
        self.code = "NSError.\(error.code)";
        self.message = error.localizedDescription;
    }
}

class DryApiClient {

    var _endpoint = "";

    init(_ endpoint: String){
        _endpoint = endpoint;
    }

    /*
var usr = "dsdd"
var pwdCode = "dsds"
let params:[String: AnyObject] = [
    "email" : usr,
    "userPwd" : pwdCode ]

var err: NSError?
request.HTTPBody = NSJSONSerialization.dataWithJSONObject(params, options: NSJSONWritingOptions.allZeros, error: &err)
*/

    func postRequest(url: String, _ data: String, _ callback: ((error: DryApiError?, data: NSData?)->())){
        var configuration = NSURLSessionConfiguration.defaultSessionConfiguration();
        var session = NSURLSession(configuration: configuration);

        // request.setValue("text/plain", forHTTPHeaderField: "Content-Type")

        let nsurl = NSURL(string: url);
        let request = NSMutableURLRequest(URL: nsurl!);
        request.HTTPMethod = "POST"
        request.HTTPBody = data.dataUsingEncoding(NSUTF8StringEncoding);

        let task = session.dataTaskWithRequest(request, { (data, response, error) in

            if(error != nil){
                return callback(error: DryApiError(error), data: nil);
            }

            if let response = response as? NSHTTPURLResponse {
                if response.statusCode != 200 {
                    return callback(error: DryApiError("not_200", "The server reply was: \(response.statusCode), we only accept 200"), data: nil);
                }
            }

            return callback(error: nil, data: data);

        });

        task.resume()
    }


    func parseResponse(data: NSData, callback: ((error: DryApiError?, response: NSDictionary?)->())){

        var result = NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.allZeros, error: nil) as? NSDictionary
        println(result)
    }

    /*
    func call<A>(methodName: String, callback: ((error: DryApiError?, arg: A?) -> ())){
        var arg1:String? = "arg1";

        if(arg1 is A){
            var x: NSDictionary? = nil;
            callback(error: x, arg: arg1 as A);
        }else if(arg1 == nil){
            var x: NSDictionary? = nil;
            callback(error: x, arg: nil);
        }else{
            println("Unexpected response, your callback didn't match the parameters returned");
            var error: NSDictionary? = ["code" : "bad_signature", "message" : "your callback didn't match the request format." ];
            let n: A? = nil;
            callback(error: error, arg: n);
        }
    }
    */

    func callSimple<A>(methodName: String, callback: ((error: DryApiError?, arg0: A?) -> ())){
        var incoming:[String: AnyObject?] = [
            "0": "zero",
            "1": nil
        ];

        var realArg0: A? = nil;
        var valid = false;

        if(incoming["0"] == nil){
            realArg0 = nil;
            valid = true;
        }else if let arg = incoming["0"] as? A{
            realArg0 = arg;
            valid = true;
        }

        if(!valid){
            let error: DryApiError? = DryApiError("bad_signature", "Your callback didn't match the request format.");
            let n: A? = nil;
            callback(error: error, arg0: n);
            return;
        }
       
        callback(error: nil, arg0: realArg0);
      
    }

    func getValue(dict: [String: AnyObject?], _ key: String) -> AnyObject? {
        if let x:AnyObject? = dict[key] {
            return(x);
        }else{ return(nil); }
    }


    func callSimple<A, B>(methodName: String, callback: ((error: DryApiError?, arg0: A?, arg1: B?) -> ())){
        var incoming:[AnyObject?] = [ "zero", "one", nil];

        let errorOut: ((_ : Int, _ : AnyObject?)->()) = { (index: Int, errorVal: AnyObject?) in
            let error: DryApiError? = DryApiError("bad_signature", "Your callback didn't match the request format for arg \(index). value: (\(errorVal))");
            let nA: A? = nil;
            let nB: B? = nil;
            callback(error: error, arg0: nA, arg1: nB);
        }

        if(incoming[0] != nil && ((incoming[0] as? A) == nil)){
            errorOut(0, incoming[0]); return;
        }

        if(incoming[1] != nil && ((incoming[1] as? B) == nil)){
            errorOut(1, incoming[1]); return;
        }

        callback(error: nil, arg0: incoming[0] as A?, arg1: incoming[1] as B?);
    }
   
    /*
    func callSimple<A, B>(methodName: String, callback: ((error: DryApiError?, arg0: A?, arg1: B?) -> ())){
        var incoming:[String: AnyObject?] = [
            "0": "zero",
            "1": nil
        ];

        let errorOut: ((_ : Int, _ : AnyObject?)->()) = { (index: Int, errorVal: AnyObject?) in
            let error: DryApiError? = DryApiError("bad_signature", "Your callback didn't match the request format for arg \(index). value: (\(errorVal))");
            let nA: A? = nil;
            let nB: B? = nil;
            callback(error: error, arg0: nA, arg1: nB);
        }

        var val0: A? = nil;
        var val0Valid = false;

        if(incoming["0"] == nil){
            val0 = nil;
            val0Valid = true;
        }else if let arg = incoming["0"] as? A{
            val0 = arg;
            val0Valid = true;
        }

        if(!val0Valid){
            errorOut(0, getValue(incoming, "0"));
            return;
        }

        var val1: B? = nil;
        var val1Valid = false;

        if(incoming["1"] == nil){
            val1 = nil;
            val1Valid = true;
        }else if let arg = incoming["1"] as? B{
            val1 = arg;
            val1Valid = true;
        }

        if(val1Valid){
            errorOut(1, getValue(incoming, "1"));
            return;
        }
       
        callback(error: nil, arg0: val0, arg1: val1);
    }
    */

    /*
    func callSimple<A, B, C>(methodName: String, callback: ((error: DryApiError?, arg0: A?, arg1: B?, arg2: C?) -> ())){
        var incoming:[String: AnyObject?] = [
            "0": "zero",
            "1": nil
        ];

        var val0: A? = nil;
        var val0Valid = false;

        if(incoming["0"] == nil){
            val0 = nil;
            val0Valid = true;
        }else if let arg = incoming["0"] as? A{
            val0 = arg;
            val0Valid = true;
        }

        if(!val0Valid){
            let x = incoming["0"];
            let error: DryApiError? = DryApiError("bad_signature", "Your callback didn't match the request format for arg 0. value: (\(x))");
            let nA: A? = nil;
            let nB: B? = nil;
            callback(error: error, arg0: nA, arg1: nB);
            return;
        }

        var val1: B? = nil;
        var val1Valid = false;

        if(incoming["1"] == nil){
            val1 = nil;
            val1Valid = true;
        }else if let arg = incoming["1"] as? B{
            val1 = arg;
            val1Valid = true;
        }

        if(val1Valid){
            let x = incoming["1"];
            let error: DryApiError? = DryApiError("bad_signature", "Your callback didn't match the request format for arg 1. value: (\(x))");
            let nA: A? = nil;
            let nB: B? = nil;
            callback(error: error, arg0: nA, arg1: nB);
            return;
        }
       
        callback(error: nil, arg0: val0, arg1: val1);
    }
    */


    func titlesFromJSON(data: NSData) -> [String] {
        var titles = [String]()
        var jsonError: NSError?
        
        if let json = NSJSONSerialization.JSONObjectWithData(data, options: nil, error: &jsonError) as? NSDictionary {
            if let feed = json["feed"] as? NSDictionary {
                if let entries = feed["entry"] as? NSArray {
                    for entry in entries {
                        if let name = entry["im:name"] as? NSDictionary {
                            if let label = name["label"] as? String {
                                titles.append(label)
                            }
                        }
                    }
                }
            }
        } else {
            if let unwrappedError = jsonError {
                println("json error: \(unwrappedError)")
            }
        }
        
        return titles
    }
}
