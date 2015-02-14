
class DryApiClient : DryApiClientParent {

{{#methods}}

{{{.}}}

{{/methods}}

    /*
    func call<AA: NSObject, AB: NSObject, A, B>(methodName: String, _ sendArg0: AA, _ sendArg1: AB, callback: ((error: DryApiError?, arg0: A?, arg1: B?) -> ())){
        println(name);
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "params": ["0", "1"],
            "0": sendArg0,
            "1": sendArg1
        ];

        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 

            if(error != nil){ return callback(error: error, arg0: nil, arg1: nil); }

            var args = args!;

            func errorOut(i: Int, e: AnyObject?){ 
                let error = self.badSignatureError(i, e);
                callback(error: error, arg0: nil, arg1: nil);
            }

            if(args.count <= 0){ args[0] = nil; }
            if(args[0] != nil && ((args[0] as? A) == nil)){
                return errorOut(0, args[0]);
            }

            if(args.count <= 1){ args[1] = nil; }
            if(args[1] != nil && ((args[1] as? B) == nil)){
                return errorOut(1, args[1]); 
            }

            callback(error: nil, arg0: args[0] as A?, arg1: args[1] as B?);
        });
    }

    func call<AA: NSObject, AB: NSObject, A, B, C>(methodName: String, _ sendArg0: AA, _ sendArg1: AB, callback: ((error: DryApiError?, arg0: A?, arg1: B?, arg2: C?) -> ())){
        var outgoingMessage: NSMutableDictionary = [
            "id": NSUUID().UUIDString,
            "method": methodName,
            "params": ["0", "1"],
            "0": sendArg0,
            "1": sendArg1
        ];

        self.callEndpointGetArgs(outgoingMessage, { (error, args) in 

            if(error != nil){ return callback(error: error, arg0: nil, arg1: nil, arg2: nil); }

            var args = args!;

            func errorOut(i: Int, e: AnyObject?){ 
                let error = self.badSignatureError(i, e);
                callback(error: error, arg0: nil, arg1: nil, arg2: nil);
            }

            if(args.count <= 0){ args.append(nil); }
            if(args[0] != nil && ((args[0] as? A) == nil)){
                return errorOut(0, args[0]);
            }

            if(args.count <= 1){ args.append(nil); }
            if(args[1] != nil && ((args[1] as? B) == nil)){
                return errorOut(1, args[1]); 
            }

            if(args.count <= 2){ args.append(nil); }
            if(args[2] != nil && ((args[2] as? B) == nil)){
                return errorOut(2, args[2]); 
            }

            callback(error: nil, arg0: args[0] as A?, arg1: args[1] as B?, arg2: args[2] as C?);
        });
    }
    */
}

