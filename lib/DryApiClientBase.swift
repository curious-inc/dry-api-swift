
import Foundation;

public class DryApiError: NSObject {

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

    init(_ error: NSDictionary){
        if let code = error["code"] as? NSString {
            self.code = code;
        }else{ self.code = "no_code"; }

        if let message = error["message"] as? NSString {
            self.message = message;
        }else{ self.message = "no_message"; }
    }

    func description() -> String {
        return("code: \(self.code) message: \(self.message)");
    }
}

public class DryApiClientBase : NSObject, NSURLSessionDelegate {

    var _endpoint = "";
    
    public var debug = false;

    public let null = NSNull();

    init(_ endpoint: String){
        _endpoint = endpoint;
    }

    var _tags = NSMutableDictionary();

    func tags() -> NSDictionary {
        return(_tags.copy() as NSDictionary);
    }

    func tags(key: String) -> String? {
        return(_tags[key] as String?);
    }

    func tags(key: String, _ val: String) -> DryApiClientBase {
        _tags[key] = val;
        return (self);
    }

    var _unsafeDomains: Array<String> = [];

    func addUnsafeDomain(domain: String) {
        _unsafeDomains.append(domain);
    }

    func URLSession(session: NSURLSession, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: ((NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> ())){
        if(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust){
            // println("https circumvent test host: \(challenge.protectionSpace.host)");
            if(find(_unsafeDomains, challenge.protectionSpace.host) != nil){
                let credential: NSURLCredential = NSURLCredential(trust: challenge.protectionSpace.serverTrust);
                completionHandler(.UseCredential, credential);
            }else{
                completionHandler(.CancelAuthenticationChallenge, nil);
            }
        }
    }

    func postRequest(url: String, _ data: NSData, _ callback: ((error: DryApiError?, data: NSData?)->())){
        var configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration();
        configuration.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicy.Never
        var session: NSURLSession!;

        if(_unsafeDomains.count > 0){
            session = NSURLSession(configuration: configuration, delegate: self, delegateQueue: nil);
        }else{
            session = NSURLSession(configuration: configuration);
        }

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

    func dataToString(data: NSData) -> String{
        if let string = NSString(data: data, encoding: NSUTF8StringEncoding) {
            return(string);
        }else{ return(""); }
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

            if(self.debug){ 
                println("reponse json: \(response)");
                println("reponse string: \(self.dataToString(data))");
            }

            if let params = response["params"] as? NSArray {

                let error:AnyObject? = response["error"];

                if(!(error is NSNull)){
                    if let error = error as NSDictionary? {
                        return callback(error: DryApiError(error), args: nil);
                    }else{
                        return callback(error: DryApiError("no_code", "object: \(error)"), args: nil);
                    }
                }

                for key in params {
                    if let key = key as? String {
                        if(key == "error"){ continue; }
                        if let val = response[key] as? NSNull {
                            args.append(nil);
                        }else{
                            args.append(response[key]);
                        }
                    }else{
                        return callback(error: DryApiError("malformed_response", "Params contained non string. params: \(params)"), args: nil); 
                    }
                }

                if(self.debug){ println("processed args: \(args)"); }
                return callback(error: nil, args: args);

            }else{
                return callback(error: DryApiError("malformed_response", "Response was missing params."), args: nil); 
            }
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

    func logOutgoingMessage(data: NSData?){
        if let data = data {
            if let str = NSString(data: data, encoding: NSUTF8StringEncoding) {
                println("outgoingMessage data(string): \(str)");
            }
        }
    }

    func callEndpointGetArgs(outgoingMessage: NSDictionary, callback: ((error: DryApiError?, args: [AnyObject?]?)->())){
        self.dataify(outgoingMessage, { (error, data) in 
            if(error != nil){ return callback(error: error, args: nil); }

            if(self.debug){ self.logOutgoingMessage(data); }

            self.postRequest(self._endpoint, data!, { (error, response) in
                if(error != nil){ return callback(error: error, args: nil); }

                self.responseToArgs(response, { (error, args) in 
                    if(error != nil){ return callback(error: error, args: nil); }
                    else{ callback(error: nil, args: args); }
                });
            });
        });
    }

    func badSignatureError(index: Int, _ val: AnyObject?) -> DryApiError{
        let error: DryApiError = DryApiError("bad_signature", "Your callback didn't match the request format for arg[\(index)]. value: (\(val))");
        return(error);
    }
}

