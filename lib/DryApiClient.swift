
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
    
    let debug = true;

    init(_ endpoint: String){
        _endpoint = endpoint;
    }

    func postRequest(url: String, _ data: NSData, _ callback: ((error: DryApiError?, data: NSData?)->())){
        var configuration = NSURLSessionConfiguration.defaultSessionConfiguration();
        var session = NSURLSession(configuration: configuration);

        // request.setValue("text/plain", forHTTPHeaderField: "Content-Type")

        let nsurl = NSURL(string: url);
        let request = NSMutableURLRequest(URL: nsurl!);
        request.HTTPMethod = "POST";
        request.HTTPBody = data;

        let task = session.dataTaskWithRequest(request, { (data, response, error) in

            if(error != nil){ return callback(error: DryApiError(error), data: nil); }

            if let response = response as? NSHTTPURLResponse {
                if response.statusCode != 200 {
                    return callback(error: DryApiError("not_200", "The server reply was: \(response.statusCode), we only accept 200"), data: nil);
                }
            }

            return callback(error: nil, data: data);

        });

        task.resume()
    }

    func postRequest(url: String, _ data: String, _ callback: ((error: DryApiError?, data: NSData?)->())){
        return postRequest(url, data.dataUsingEncoding(NSUTF8StringEncoding)!, callback);
    }


    func responseToArgs(data: NSData?, callback: ((error: DryApiError?, args: [AnyObject?]?)->())){

        var args: [AnyObject?] = [];
        
        if(data == nil){ callback(error: DryApiError("no_data", "No data received."), args: nil); }

        let data = data!;

        self.parse(data, { (error, response) in 
            if(error != nil){ return callback(error: error, args: nil); }

            let response = response!

            println("response: \(response)");
            args.append("zero");
            args.append("one");
            callback(error: nil, args: args);
            // if let val = result["1"] as? NSNull {
            //     println("IS NULL: TRUE");
            // }
        });
    }

    func parse(data: NSData, callback: ((error: DryApiError?, response: NSDictionary?)->())){
        var jsonError: NSError? = nil; 
        var result = NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.allZeros, error: &jsonError) as? NSDictionary

        if(result != nil){ callback(error: nil, response: result); }
        else{ callback(error: DryApiError(jsonError!), response: nil); }
    }

    func dataify(value: AnyObject, _ callback: ((error: DryApiError?, response: NSData?)->())){
        var jsonError: NSError? = nil; 
        if let data = NSJSONSerialization.dataWithJSONObject(value, options: nil, error: &jsonError) {
            callback(error: nil, response: data);
        }else{
            callback(error: DryApiError(jsonError!), response: nil);
        }
    }

    func stringify(value: AnyObject, _ prettyPrinted: Bool = false) -> String {
        var options = prettyPrinted ? NSJSONWritingOptions.PrettyPrinted : nil
        if NSJSONSerialization.isValidJSONObject(value) {
            if let data = NSJSONSerialization.dataWithJSONObject(value, options: nil, error: nil) {
                if let string = NSString(data: data, encoding: NSUTF8StringEncoding) {
                    return string
                }
            }
        }
        return ""
    }

    func getValue(dict: [String: AnyObject?], _ key: String) -> AnyObject? {
        if let x:AnyObject? = dict[key] {
            return(x);
        }else{ return(nil); }
    }

    // func call<AA, AB, A, B>(methodName: String, _ sendArg0: AA?, _ sendArg1: AB?, callback: ((error: DryApiError?, arg0: A?, arg1: B?) -> ())){
        // callback(error: nil, arg0: nil, arg1: nil);
    // }

    func call<AA: NSObject, AB: NSObject, A, B>(methodName: String, _ sendArg0: AA, _ sendArg1: AB, callback: ((error: DryApiError?, arg0: A?, arg1: B?) -> ())){
    // func call<AA: AnyObject, AB: AnyObject, A: AnyObject, B: AnyObject>(methodName: String, _ sendArg0: AA?, _ sendArg1: AB?, callback: ((error: DryApiError?, arg0: A?, arg1: B?) -> ())){
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "params": ["0", "1"],
            "0": sendArg0,
            "1": sendArg1
        ];


        if(self.debug){
            var str = stringify(outgoingMessage, true);
            println("outgoingMessage str: \(str)");
        }

        self.dataify(outgoingMessage, { (error, data) in 

            if(error != nil){ return callback(error: error, arg0: nil, arg1: nil); }
            println("outgoingMessage data: \(data)");
            if let data = data {
                if let str = NSString(data: data, encoding: NSUTF8StringEncoding) {
                    println("outgoingMessage data(string): \(str)");
                }
            }

            self.postRequest(self._endpoint, data!, { (error, response) in

                if(error != nil){ return callback(error: error, arg0: nil, arg1: nil); }

                self.responseToArgs(response, { (error, oargs) in 

                    if(error != nil){ return callback(error: error, arg0: nil, arg1: nil); }
        
                    let args = oargs!;

                    // This is hella touchy. If you define AnyObject? as Any? you segfault the compiler
                    // This is one of a few segfaults i've had to work around.
                    let errorOut: ((_ : Int, _ : AnyObject?)->()) = { (i: Int, e: AnyObject?) in
                        let error: DryApiError? = DryApiError("bad_signature", "Your callback didn't match the request format for arg \(i). value: (\(e))");
                        callback(error: error, arg0: nil, arg1: nil);
                    };

                    if(args[0] != nil && ((args[0] as? A) == nil)){
                        return errorOut(0, args[0]);
                    }

                    if(args[1] != nil && ((args[1] as? B) == nil)){
                        return errorOut(1, args[1]); 
                    }

                    callback(error: nil, arg0: args[0] as A?, arg1: args[1] as B?);

                });
            });
        });
    }

    
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
