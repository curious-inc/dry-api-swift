
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



public class DryApiClient : DryApiClientBase {


    func call(methodName: String, callback: ((error: DryApiError?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": [],
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error);
            }
            
            var args = args!;
            
            return callback(error: nil);
        });
    }



    func call<OA>(methodName: String, callback: ((error: DryApiError?, outArg0: OA?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": [],
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            return callback(error: nil, outArg0: args[0] as OA?);
        });
    }



    func call<OA, OB>(methodName: String, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": [],
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?);
        });
    }



    func call<OA, OB, OC>(methodName: String, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": [],
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?);
        });
    }



    func call<OA, OB, OC, OD>(methodName: String, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": [],
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?);
        });
    }



    func call<OA, OB, OC, OD, OE>(methodName: String, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": [],
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?);
        });
    }



    func call<OA, OB, OC, OD, OE, OF>(methodName: String, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": [],
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?);
        });
    }



    func call<OA, OB, OC, OD, OE, OF, OG>(methodName: String, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": [],
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?);
        });
    }



    func call<OA, OB, OC, OD, OE, OF, OG, OH>(methodName: String, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": [],
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?);
        });
    }



    func call<OA, OB, OC, OD, OE, OF, OG, OH, OI>(methodName: String, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": [],
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?);
        });
    }



    func call<OA, OB, OC, OD, OE, OF, OG, OH, OI, OJ>(methodName: String, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?, outArg9: OJ?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": [],
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            if(args.count <= 9){ args.append(nil); }
            if(args[9] != nil && ((args[9] as? OJ) == nil)){
                return errorOut(9, args[9]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?, outArg9: args[9] as OJ?);
        });
    }



    func call<IA: NSObject>(methodName: String, _ inArg0: IA, callback: ((error: DryApiError?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0"],
            "0": inArg0
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error);
            }
            
            var args = args!;
            
            return callback(error: nil);
        });
    }



    func call<IA: NSObject, OA>(methodName: String, _ inArg0: IA, callback: ((error: DryApiError?, outArg0: OA?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0"],
            "0": inArg0
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            return callback(error: nil, outArg0: args[0] as OA?);
        });
    }



    func call<IA: NSObject, OA, OB>(methodName: String, _ inArg0: IA, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0"],
            "0": inArg0
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?);
        });
    }



    func call<IA: NSObject, OA, OB, OC>(methodName: String, _ inArg0: IA, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0"],
            "0": inArg0
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?);
        });
    }



    func call<IA: NSObject, OA, OB, OC, OD>(methodName: String, _ inArg0: IA, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0"],
            "0": inArg0
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?);
        });
    }



    func call<IA: NSObject, OA, OB, OC, OD, OE>(methodName: String, _ inArg0: IA, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0"],
            "0": inArg0
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?);
        });
    }



    func call<IA: NSObject, OA, OB, OC, OD, OE, OF>(methodName: String, _ inArg0: IA, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0"],
            "0": inArg0
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?);
        });
    }



    func call<IA: NSObject, OA, OB, OC, OD, OE, OF, OG>(methodName: String, _ inArg0: IA, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0"],
            "0": inArg0
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?);
        });
    }



    func call<IA: NSObject, OA, OB, OC, OD, OE, OF, OG, OH>(methodName: String, _ inArg0: IA, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0"],
            "0": inArg0
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?);
        });
    }



    func call<IA: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI>(methodName: String, _ inArg0: IA, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0"],
            "0": inArg0
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?);
        });
    }



    func call<IA: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI, OJ>(methodName: String, _ inArg0: IA, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?, outArg9: OJ?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0"],
            "0": inArg0
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            if(args.count <= 9){ args.append(nil); }
            if(args[9] != nil && ((args[9] as? OJ) == nil)){
                return errorOut(9, args[9]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?, outArg9: args[9] as OJ?);
        });
    }



    func call<IA: NSObject, IB: NSObject>(methodName: String, _ inArg0: IA, _ inArg1: IB, callback: ((error: DryApiError?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1"],
            "0": inArg0,
            "1": inArg1
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error);
            }
            
            var args = args!;
            
            return callback(error: nil);
        });
    }



    func call<IA: NSObject, IB: NSObject, OA>(methodName: String, _ inArg0: IA, _ inArg1: IB, callback: ((error: DryApiError?, outArg0: OA?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1"],
            "0": inArg0,
            "1": inArg1
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            return callback(error: nil, outArg0: args[0] as OA?);
        });
    }



    func call<IA: NSObject, IB: NSObject, OA, OB>(methodName: String, _ inArg0: IA, _ inArg1: IB, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1"],
            "0": inArg0,
            "1": inArg1
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?);
        });
    }



    func call<IA: NSObject, IB: NSObject, OA, OB, OC>(methodName: String, _ inArg0: IA, _ inArg1: IB, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1"],
            "0": inArg0,
            "1": inArg1
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?);
        });
    }



    func call<IA: NSObject, IB: NSObject, OA, OB, OC, OD>(methodName: String, _ inArg0: IA, _ inArg1: IB, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1"],
            "0": inArg0,
            "1": inArg1
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?);
        });
    }



    func call<IA: NSObject, IB: NSObject, OA, OB, OC, OD, OE>(methodName: String, _ inArg0: IA, _ inArg1: IB, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1"],
            "0": inArg0,
            "1": inArg1
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?);
        });
    }



    func call<IA: NSObject, IB: NSObject, OA, OB, OC, OD, OE, OF>(methodName: String, _ inArg0: IA, _ inArg1: IB, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1"],
            "0": inArg0,
            "1": inArg1
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?);
        });
    }



    func call<IA: NSObject, IB: NSObject, OA, OB, OC, OD, OE, OF, OG>(methodName: String, _ inArg0: IA, _ inArg1: IB, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1"],
            "0": inArg0,
            "1": inArg1
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?);
        });
    }



    func call<IA: NSObject, IB: NSObject, OA, OB, OC, OD, OE, OF, OG, OH>(methodName: String, _ inArg0: IA, _ inArg1: IB, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1"],
            "0": inArg0,
            "1": inArg1
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?);
        });
    }



    func call<IA: NSObject, IB: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI>(methodName: String, _ inArg0: IA, _ inArg1: IB, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1"],
            "0": inArg0,
            "1": inArg1
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?);
        });
    }



    func call<IA: NSObject, IB: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI, OJ>(methodName: String, _ inArg0: IA, _ inArg1: IB, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?, outArg9: OJ?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1"],
            "0": inArg0,
            "1": inArg1
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            if(args.count <= 9){ args.append(nil); }
            if(args[9] != nil && ((args[9] as? OJ) == nil)){
                return errorOut(9, args[9]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?, outArg9: args[9] as OJ?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, callback: ((error: DryApiError?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error);
            }
            
            var args = args!;
            
            return callback(error: nil);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, OA>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, callback: ((error: DryApiError?, outArg0: OA?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            return callback(error: nil, outArg0: args[0] as OA?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, OA, OB>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, OA, OB, OC>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, OA, OB, OC, OD>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, OA, OB, OC, OD, OE>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, OA, OB, OC, OD, OE, OF>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, OA, OB, OC, OD, OE, OF, OG>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, OA, OB, OC, OD, OE, OF, OG, OH>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI, OJ>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?, outArg9: OJ?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            if(args.count <= 9){ args.append(nil); }
            if(args[9] != nil && ((args[9] as? OJ) == nil)){
                return errorOut(9, args[9]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?, outArg9: args[9] as OJ?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, callback: ((error: DryApiError?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error);
            }
            
            var args = args!;
            
            return callback(error: nil);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, OA>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, callback: ((error: DryApiError?, outArg0: OA?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            return callback(error: nil, outArg0: args[0] as OA?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, OA, OB>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, OA, OB, OC>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, OA, OB, OC, OD>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, OA, OB, OC, OD, OE>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, OA, OB, OC, OD, OE, OF>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, OA, OB, OC, OD, OE, OF, OG>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, OA, OB, OC, OD, OE, OF, OG, OH>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI, OJ>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?, outArg9: OJ?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            if(args.count <= 9){ args.append(nil); }
            if(args[9] != nil && ((args[9] as? OJ) == nil)){
                return errorOut(9, args[9]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?, outArg9: args[9] as OJ?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, callback: ((error: DryApiError?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error);
            }
            
            var args = args!;
            
            return callback(error: nil);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, OA>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, callback: ((error: DryApiError?, outArg0: OA?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            return callback(error: nil, outArg0: args[0] as OA?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, OA, OB>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, OA, OB, OC>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, OA, OB, OC, OD>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, OA, OB, OC, OD, OE>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, OA, OB, OC, OD, OE, OF>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, OA, OB, OC, OD, OE, OF, OG>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, OA, OB, OC, OD, OE, OF, OG, OH>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI, OJ>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?, outArg9: OJ?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            if(args.count <= 9){ args.append(nil); }
            if(args[9] != nil && ((args[9] as? OJ) == nil)){
                return errorOut(9, args[9]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?, outArg9: args[9] as OJ?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, callback: ((error: DryApiError?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error);
            }
            
            var args = args!;
            
            return callback(error: nil);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, OA>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, callback: ((error: DryApiError?, outArg0: OA?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            return callback(error: nil, outArg0: args[0] as OA?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, OA, OB>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, OA, OB, OC>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, OA, OB, OC, OD>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, OA, OB, OC, OD, OE>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, OA, OB, OC, OD, OE, OF>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, OA, OB, OC, OD, OE, OF, OG>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, OA, OB, OC, OD, OE, OF, OG, OH>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI, OJ>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?, outArg9: OJ?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            if(args.count <= 9){ args.append(nil); }
            if(args[9] != nil && ((args[9] as? OJ) == nil)){
                return errorOut(9, args[9]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?, outArg9: args[9] as OJ?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, callback: ((error: DryApiError?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error);
            }
            
            var args = args!;
            
            return callback(error: nil);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, OA>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, callback: ((error: DryApiError?, outArg0: OA?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            return callback(error: nil, outArg0: args[0] as OA?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, OA, OB>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, OA, OB, OC>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, OA, OB, OC, OD>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, OA, OB, OC, OD, OE>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, OA, OB, OC, OD, OE, OF>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, OA, OB, OC, OD, OE, OF, OG>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, OA, OB, OC, OD, OE, OF, OG, OH>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI, OJ>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?, outArg9: OJ?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            if(args.count <= 9){ args.append(nil); }
            if(args[9] != nil && ((args[9] as? OJ) == nil)){
                return errorOut(9, args[9]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?, outArg9: args[9] as OJ?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, callback: ((error: DryApiError?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error);
            }
            
            var args = args!;
            
            return callback(error: nil);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, OA>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, callback: ((error: DryApiError?, outArg0: OA?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            return callback(error: nil, outArg0: args[0] as OA?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, OA, OB>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, OA, OB, OC>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, OA, OB, OC, OD>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, OA, OB, OC, OD, OE>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, OA, OB, OC, OD, OE, OF>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, OA, OB, OC, OD, OE, OF, OG>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, OA, OB, OC, OD, OE, OF, OG, OH>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI, OJ>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?, outArg9: OJ?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            if(args.count <= 9){ args.append(nil); }
            if(args[9] != nil && ((args[9] as? OJ) == nil)){
                return errorOut(9, args[9]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?, outArg9: args[9] as OJ?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, callback: ((error: DryApiError?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error);
            }
            
            var args = args!;
            
            return callback(error: nil);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, OA>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, callback: ((error: DryApiError?, outArg0: OA?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            return callback(error: nil, outArg0: args[0] as OA?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, OA, OB>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, OA, OB, OC>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, OA, OB, OC, OD>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, OA, OB, OC, OD, OE>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, OA, OB, OC, OD, OE, OF>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, OA, OB, OC, OD, OE, OF, OG>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, OA, OB, OC, OD, OE, OF, OG, OH>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI, OJ>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?, outArg9: OJ?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            if(args.count <= 9){ args.append(nil); }
            if(args[9] != nil && ((args[9] as? OJ) == nil)){
                return errorOut(9, args[9]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?, outArg9: args[9] as OJ?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, IJ: NSObject>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, _ inArg9: IJ, callback: ((error: DryApiError?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8","9"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8,
            "9": inArg9
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error);
            }
            
            var args = args!;
            
            return callback(error: nil);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, IJ: NSObject, OA>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, _ inArg9: IJ, callback: ((error: DryApiError?, outArg0: OA?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8","9"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8,
            "9": inArg9
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            return callback(error: nil, outArg0: args[0] as OA?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, IJ: NSObject, OA, OB>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, _ inArg9: IJ, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8","9"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8,
            "9": inArg9
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, IJ: NSObject, OA, OB, OC>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, _ inArg9: IJ, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8","9"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8,
            "9": inArg9
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, IJ: NSObject, OA, OB, OC, OD>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, _ inArg9: IJ, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8","9"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8,
            "9": inArg9
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, IJ: NSObject, OA, OB, OC, OD, OE>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, _ inArg9: IJ, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8","9"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8,
            "9": inArg9
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, IJ: NSObject, OA, OB, OC, OD, OE, OF>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, _ inArg9: IJ, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8","9"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8,
            "9": inArg9
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, IJ: NSObject, OA, OB, OC, OD, OE, OF, OG>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, _ inArg9: IJ, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8","9"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8,
            "9": inArg9
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, IJ: NSObject, OA, OB, OC, OD, OE, OF, OG, OH>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, _ inArg9: IJ, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8","9"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8,
            "9": inArg9
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, IJ: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, _ inArg9: IJ, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8","9"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8,
            "9": inArg9
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, ID: NSObject, IE: NSObject, IF: NSObject, IG: NSObject, IH: NSObject, II: NSObject, IJ: NSObject, OA, OB, OC, OD, OE, OF, OG, OH, OI, OJ>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ inArg3: ID, _ inArg4: IE, _ inArg5: IF, _ inArg6: IG, _ inArg7: IH, _ inArg8: II, _ inArg9: IJ, callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?, outArg3: OD?, outArg4: OE?, outArg5: OF?, outArg6: OG?, outArg7: OH?, outArg8: OI?, outArg9: OJ?)->()))    {
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "tags": self.tags(),
            "params": ["0","1","2","3","4","5","6","7","8","9"],
            "0": inArg0,
            "1": inArg1,
            "2": inArg2,
            "3": inArg3,
            "4": inArg4,
            "5": inArg5,
            "6": inArg6,
            "7": inArg7,
            "8": inArg8,
            "9": inArg9
        ];
        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 
            if(error != nil){
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            func errorOut(i: Int, e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil, outArg1: nil, outArg2: nil, outArg3: nil, outArg4: nil, outArg5: nil, outArg6: nil, outArg7: nil, outArg8: nil, outArg9: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? OB) == nil)){
                return errorOut(1, args[1]);
            }
            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? OC) == nil)){
                return errorOut(2, args[2]);
            }
            if(args.count <= 3){ args.append(nil); }
            if(args[3] != nil && ((args[3] as? OD) == nil)){
                return errorOut(3, args[3]);
            }
            if(args.count <= 4){ args.append(nil); }
            if(args[4] != nil && ((args[4] as? OE) == nil)){
                return errorOut(4, args[4]);
            }
            if(args.count <= 5){ args.append(nil); }
            if(args[5] != nil && ((args[5] as? OF) == nil)){
                return errorOut(5, args[5]);
            }
            if(args.count <= 6){ args.append(nil); }
            if(args[6] != nil && ((args[6] as? OG) == nil)){
                return errorOut(6, args[6]);
            }
            if(args.count <= 7){ args.append(nil); }
            if(args[7] != nil && ((args[7] as? OH) == nil)){
                return errorOut(7, args[7]);
            }
            if(args.count <= 8){ args.append(nil); }
            if(args[8] != nil && ((args[8] as? OI) == nil)){
                return errorOut(8, args[8]);
            }
            if(args.count <= 9){ args.append(nil); }
            if(args[9] != nil && ((args[9] as? OJ) == nil)){
                return errorOut(9, args[9]);
            }
            return callback(error: nil, outArg0: args[0] as OA?, outArg1: args[1] as OB?, outArg2: args[2] as OC?, outArg3: args[3] as OD?, outArg4: args[4] as OE?, outArg5: args[5] as OF?, outArg6: args[6] as OG?, outArg7: args[7] as OH?, outArg8: args[8] as OI?, outArg9: args[9] as OJ?);
        });
    }



}

