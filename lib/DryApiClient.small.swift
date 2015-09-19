
import Foundation;

public class DryApiError: NSObject {

    public let code: String;
    public let message: String;

    init(_ code: String, _ message: String){
        self.code = code;
        self.message = message;
    }

    class func withError(error: NSError) -> DryApiError {
        return(DryApiError("NSError.\(error.code)", error.localizedDescription));
    }

    class func withDictionary(dictionary: NSDictionary) -> DryApiError {
        var code = "no_code";
        var message = "no_message";

        if let c = dictionary["code"] as? NSString {
            code = c as String;
        }

        if let m = dictionary["message"] as? NSString {
            message = m as String;
        }

        return(DryApiError(code, message));
    }

    public override var description: String {
        return("code: \(self.code) message: \(self.message)");
    }
}

public class DryApiClientBase : NSObject, NSURLSessionDelegate, NSURLSessionTaskDelegate {

    var _endpoint = "";
    
    public var debug = false;

    public let null = NSNull();

    init(_ endpoint: String){
        _endpoint = endpoint;
    }

    var _tags = NSMutableDictionary();

    func tags() -> NSDictionary {
        return(_tags.copy() as! NSDictionary);
    }

    func tags(key: String) -> String? {
        return(_tags[key] as! String?);
    }

    func tags(key: String, _ val: String) -> DryApiClientBase {
        _tags[key] = val;
        return (self);
    }

    var _unsafeDomains: Array<String> = [];

    func addUnsafeDomain(domain: String) {
        _unsafeDomains.append(domain);
    }
    
    public func URLSession(_ session: NSURLSession, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {
        if(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust){
            // print("https circumvent test host: \(challenge.protectionSpace.host)");
            if(_unsafeDomains.indexOf(challenge.protectionSpace.host) != nil){
                var credential: NSURLCredential = NSURLCredential(trust: challenge.protectionSpace.serverTrust!);
                completionHandler(.UseCredential, credential);
            }else{
                completionHandler(.CancelAuthenticationChallenge, nil);
            }
        }
    }

    var _session: NSURLSession?;

    func session() -> NSURLSession {

        if(_session != nil){ return(_session!); }

        var configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration();
        configuration.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicy.Never

        if(_unsafeDomains.count > 0){
            _session = NSURLSession(configuration: configuration, delegate: self, delegateQueue: nil);
        }else{
            _session = NSURLSession(configuration: configuration);
        }

        return(_session!);
    }

    func postRequest(url: String, _ data: NSData, _ callback: ((error: DryApiError?, data: NSData?)->())){
        let session = self.session();

        let nsurl = NSURL(string: url);
        let request = NSMutableURLRequest(URL: nsurl!);
        request.HTTPMethod = "POST";
        request.HTTPBody = data;

        // request.setValue("text/plain", forHTTPHeaderField: "Content-Type")

        let task = session.dataTaskWithRequest(request, completionHandler: { (data, response, error) in

            if(error != nil){ return callback(error: DryApiError.withError(error!), data: nil); }

            if let response = response as? NSHTTPURLResponse {
                if response.statusCode != 200 {
                    return callback(error: DryApiError("not_200", "The server reply was: \(response.statusCode), we only accept 200"), data: nil);
                }
            }

            return callback(error: nil, data: data);

        });

        task.resume()
    }

    func postRequestWithString(url: String, _ data: String, _ callback: ((error: DryApiError?, data: NSData?)->())){
        return postRequest(url, data.dataUsingEncoding(NSUTF8StringEncoding)!, callback);
    }

    func dataToString(data: NSData) -> String{
        if let string = NSString(data: data, encoding: NSUTF8StringEncoding) {
            return(string as String);
        }else{ return(""); }
    }

    func responseToArgs(data: NSData?, _ callback: ((error: DryApiError?, args: [AnyObject?]?)->())){

        var args: [AnyObject?] = [];
        
        if(data == nil){ callback(error: DryApiError("no_data", "No data received."), args: nil); }

        let data = data!;

        self.parse(data, { (error, response) in 
            if(error != nil){ return callback(error: error, args: nil); }

            let response = response!

            if(self.debug){ 
                print("reponse json: \(response)");
                print("reponse string: \(self.dataToString(data))");
            }

            if let params = response["params"] as? NSArray {

                let error:AnyObject? = response["error"];

                if(!(error is NSNull)){
                    if let error = error as? NSDictionary? {
                        if let error = error {
                            return callback(error: DryApiError.withDictionary(error), args: nil);
                        }
                    }
                    return callback(error: DryApiError("no_code", "object: \(error)"), args: nil);
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

                if(self.debug){ print("processed args: \(args)"); }
                return callback(error: nil, args: args);

            }else{
                return callback(error: DryApiError("malformed_response", "Response was missing params."), args: nil); 
            }
        });
    }

    func parse(data: NSData, _ callback: ((error: DryApiError?, response: NSDictionary?)->())){

        do {
            // let result = try NSJSONSerialization.JSONObjectWithData(data, options:NSJSONReadingOptions(rawValue: 0)) as? NSDictionary
            let result = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions()) as? NSDictionary
            callback(error: nil, response: result);
        } catch let error as NSError {
            callback(error: DryApiError.withError(error), response: nil); 
        }

        // var result = NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.allZeros, error: &jsonError) as? NSDictionary
    }

    func dataify(value: AnyObject, _ callback: ((error: DryApiError?, response: NSData?)->())){
        do {
            let data = try NSJSONSerialization.dataWithJSONObject(value, options: NSJSONWritingOptions()) 
            callback(error: nil, response: data);
        } catch let error as NSError {
            callback(error: DryApiError.withError(error), response: nil); 
        }
    }

    func getValue(dict: [String: AnyObject?], _ key: String) -> AnyObject? {
        if let x:AnyObject? = dict[key] {
            return(x);
        }else{ return(nil); }
    }

    func logOutgoingMessage(data: NSData?){
        if let data = data {
            if let str = NSString(data: data, encoding: NSUTF8StringEncoding) {
                print("outgoingMessage data(string): \(str)");
            }
        }
    }

    func callEndpointGetArgs(outgoingMessage: NSDictionary, _ callback: ((error: DryApiError?, args: [AnyObject?]?)->())){
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


    func call(methodName: String, _ callback: ((error: DryApiError?)->()))    {
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
            
            func errorOut(i: Int, _ e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error);
            }
            
            var args = args!;
            
            return callback(error: nil);
        });
    }



    func call<OA>(methodName: String, _ callback: ((error: DryApiError?, outArg0: OA?)->()))    {
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
            
            func errorOut(i: Int, _ e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            return callback(error: nil, outArg0: args[0] as! OA?);
        });
    }



    func call<OA, OB>(methodName: String, _ callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?)->()))    {
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
            
            func errorOut(i: Int, _ e: AnyObject?){
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
            return callback(error: nil, outArg0: args[0] as! OA?, outArg1: args[1] as! OB?);
        });
    }



    func call<OA, OB, OC>(methodName: String, _ callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?)->()))    {
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
            
            func errorOut(i: Int, _ e: AnyObject?){
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
            return callback(error: nil, outArg0: args[0] as! OA?, outArg1: args[1] as! OB?, outArg2: args[2] as! OC?);
        });
    }



    func call<IA: NSObject>(methodName: String, _ inArg0: IA, _ callback: ((error: DryApiError?)->()))    {
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
            
            func errorOut(i: Int, _ e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error);
            }
            
            var args = args!;
            
            return callback(error: nil);
        });
    }



    func call<IA: NSObject, OA>(methodName: String, _ inArg0: IA, _ callback: ((error: DryApiError?, outArg0: OA?)->()))    {
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
            
            func errorOut(i: Int, _ e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            return callback(error: nil, outArg0: args[0] as! OA?);
        });
    }



    func call<IA: NSObject, OA, OB>(methodName: String, _ inArg0: IA, _ callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?)->()))    {
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
            
            func errorOut(i: Int, _ e: AnyObject?){
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
            return callback(error: nil, outArg0: args[0] as! OA?, outArg1: args[1] as! OB?);
        });
    }



    func call<IA: NSObject, OA, OB, OC>(methodName: String, _ inArg0: IA, _ callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?)->()))    {
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
            
            func errorOut(i: Int, _ e: AnyObject?){
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
            return callback(error: nil, outArg0: args[0] as! OA?, outArg1: args[1] as! OB?, outArg2: args[2] as! OC?);
        });
    }



    func call<IA: NSObject, IB: NSObject>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ callback: ((error: DryApiError?)->()))    {
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
            
            func errorOut(i: Int, _ e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error);
            }
            
            var args = args!;
            
            return callback(error: nil);
        });
    }



    func call<IA: NSObject, IB: NSObject, OA>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ callback: ((error: DryApiError?, outArg0: OA?)->()))    {
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
            
            func errorOut(i: Int, _ e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            return callback(error: nil, outArg0: args[0] as! OA?);
        });
    }



    func call<IA: NSObject, IB: NSObject, OA, OB>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?)->()))    {
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
            
            func errorOut(i: Int, _ e: AnyObject?){
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
            return callback(error: nil, outArg0: args[0] as! OA?, outArg1: args[1] as! OB?);
        });
    }



    func call<IA: NSObject, IB: NSObject, OA, OB, OC>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?)->()))    {
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
            
            func errorOut(i: Int, _ e: AnyObject?){
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
            return callback(error: nil, outArg0: args[0] as! OA?, outArg1: args[1] as! OB?, outArg2: args[2] as! OC?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ callback: ((error: DryApiError?)->()))    {
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
            
            func errorOut(i: Int, _ e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error);
            }
            
            var args = args!;
            
            return callback(error: nil);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, OA>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ callback: ((error: DryApiError?, outArg0: OA?)->()))    {
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
            
            func errorOut(i: Int, _ e: AnyObject?){
                let error = self.badSignatureError(i, e);
                return callback(error: error, outArg0: nil);
            }
            
            var args = args!;
            
            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? OA) == nil)){
                return errorOut(0, args[0]);
            }
            return callback(error: nil, outArg0: args[0] as! OA?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, OA, OB>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?)->()))    {
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
            
            func errorOut(i: Int, _ e: AnyObject?){
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
            return callback(error: nil, outArg0: args[0] as! OA?, outArg1: args[1] as! OB?);
        });
    }



    func call<IA: NSObject, IB: NSObject, IC: NSObject, OA, OB, OC>(methodName: String, _ inArg0: IA, _ inArg1: IB, _ inArg2: IC, _ callback: ((error: DryApiError?, outArg0: OA?, outArg1: OB?, outArg2: OC?)->()))    {
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
            
            func errorOut(i: Int, _ e: AnyObject?){
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
            return callback(error: nil, outArg0: args[0] as! OA?, outArg1: args[1] as! OB?, outArg2: args[2] as! OC?);
        });
    }



}

