
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

    let jsonObject: [AnyObject] = [
     ["name": "John", "age": 21],
     ["name": "Bob", "age": 35],
    ]
     
    func datafy(value: AnyObject, _ options: NSJSONWritingOptions? = nil) -> NSData?{
        if NSJSONSerialization.isValidJSONObject(value) {
            if let data = NSJSONSerialization.dataWithJSONObject(value, options: nil, error: nil) {
                return data;
            }
        }
        return nil
    }

    func stringify(value: AnyObject, _ prettyPrinted: Bool = false) -> String {
        var options = prettyPrinted ? NSJSONWritingOptions.PrettyPrinted : nil
        if let data = datafy(value, options) {
            if let string = NSString(data: data, encoding: NSUTF8StringEncoding) {
                return string
            }
        }
        return ""
    }

    func getValue(dict: [String: AnyObject?], _ key: String) -> AnyObject? {
        if let x:AnyObject? = dict[key] {
            return(x);
        }else{ return(nil); }
    }

    /*
    func call<AA, AB, A, B>(methodName: String, _ sendArg0: AA?, _ sendArg1: AB?, callback: ((error: DryApiError?, arg0: A?, arg1: B?) -> ())){
        callback(error: nil, arg0: nil, arg1: nil);
    }
    */

    func call<AA: NSObject, AB: NSObject, A, B>(methodName: String, _ sendArg0: AA, _ sendArg1: AB, callback: ((error: DryApiError?, arg0: A?, arg1: B?) -> ())){
    // func call<AA: AnyObject, AB: AnyObject, A: AnyObject, B: AnyObject>(methodName: String, _ sendArg0: AA?, _ sendArg1: AB?, callback: ((error: DryApiError?, arg0: A?, arg1: B?) -> ())){
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "params": ["0", "1"],
            "0": sendArg0,
            "1": sendArg1
        ];

        // if let sendArg0 = sendArg0 as? NSObject {
            // outgoingMessage.setValue(sendArg0, forKey: "0");
        // }

        /*
        if(sendArg1 == nil){  
            outgoingMessage.setValue(NSNull(), forKey: "1");
        }else if let sendArg1 = sendArg1 as? NSObject {
            outgoingMessage.setValue(sendArg1, forKey: "1");
        }
        */

        var data = datafy(outgoingMessage);
        var str = stringify(outgoingMessage, true);

        println("outgoingMessage obj: \(outgoingMessage)");
        println("outgoingMessage str: \(str)");

        if let data = data {
            var result = NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.allZeros, error: nil) as Dictionary<String, AnyObject>
            println("parsed: \(result)");
            if let val = result["1"] as? NSNull {
                println("IS NULL: TRUE");
            }

        }

     
        callback(error: nil, arg0: nil, arg1: nil);
        return;

    }
        /*
        if let sendArg0 = sendArg0 {
            outgoingMessage.setValue(sendArg0, forKey: "0")
        }else{
            outgoingMessage.setValue(NSNull(), forKey: "0")
        }

        /*
        if let sendArg1 = sendArg1 as AnyObject {
            outgoingMessage["1"] = sendArg1;
        }else{
            outgoingMessage["1"] = NSNull();
        }
        */

        // let array: [AnyObject] = [outgoingMessage];

        // let outgoingString = toJSONData(outgoingMessage);
        let outgoingString = JSONStringify(outgoingMessage, prettyPrinted: true);

        let incoming: [AnyObject?] = ["zero", "one"];

        println("json: \(outgoingString)");

        let errorOut: ((_ : Int, _ : Any?)->()) = { (index: Int, errorVal: Any?) in
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
