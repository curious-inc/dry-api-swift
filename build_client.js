#!/usr/bin/env node

"use strict";

var _ = require('dry-underscore');

function in_arg_generic_type(i){
    var arg_type = "I" + String.fromCharCode(65 + i);
    return(arg_type);
}

function out_arg_generic_type(i){
    var arg_type = "O" + String.fromCharCode(65 + i);
    return(arg_type);
}

function generic_signature(in_args, out_args){

    //<IA: NSObject, IB: NSObject, OA, OB>(methodName: String, _ sendArg0: IA, _ sendArg1: IB, callback: ((error: DryApiError?, arg0: OA?, arg1: OB?) -> ())){
    
    var sig = "";
    var first = true;
    _.for(in_args, function(i){
        if(sig != ""){ sig += ", "; }
        sig += in_arg_generic_type(i) + ": NSObject";
        first = false;
    });

    _.for(out_args, function(i){
        if(sig != ""){ sig += ", "; }
        sig += out_arg_generic_type(i);
    });
 
    return(sig);
}

function parameter_signature(in_args, out_args){
    //<IA: NSObject, IB: NSObject, OA, OB>(methodName: String, _ sendArg0: IA, _ sendArg1: IB, callback: ((error: DryApiError?, arg0: oa?, arg1: OB?) -> ())){
    // (methodName: String, _ sendArg0: AA, _ sendArg1: AB, callback: ((error: DryApiError?, arg0: A?, arg1: B?) -> ()))

    var sig = "methodName: String";

    _.for(in_args, function(i){
        sig += ", _ inArg" + i + ": " + in_arg_generic_type(i);
    });

    sig += ", callback: ((error: DryApiError?";

    _.for(out_args, function(i){
        sig += ", outArg" + i + ": " + out_arg_generic_type(i) + "?";
    });

    sig += ")->())";
 
    return(sig);
}

function make_method_signature(in_args, out_args){
    var sig = "";

    if(in_args == 0 && out_args == 0){
        sig = "func call(" + parameter_signature(in_args, out_args)  + ")";
    }else{
        sig = "func call<" + generic_signature(in_args, out_args) + ">(" + parameter_signature(in_args, out_args)  + ")";
    }
    return(sig);
}

function make_outgoing_message(body, in_args, out_args){

    body.add_line('var outgoingMessage: NSMutableDictionary = [');
    body.in(4);
    body.add_line('"id": NSUUID().UUIDString,');
    body.add_line('"method": methodName,');
    body.add_line('"tags": self.tags(),');

    var params = [];
    _.for(in_args, function(i){
        params.push(_.s(i));
    });
    body.add_line('"params": ' + _.stringify(params) + ',');

    _.for(in_args, function(i){
        body.add_line('"' + _.s(i) + '": inArg' + i + ((i+1 == in_args) ? "" : ","));
    });
 
    body.out(4);
    body.add_line("];");
}

function make_error_call(in_args, out_args){
    // return callback(error: error, arg0: nil, arg1: nil);
   
    var call = "return callback(error: error";

    _.for(out_args, function(i){
        call += ", outArg" + i + ": nil";
    });

    call += ");";

    return(call);
}

function make_callback_call(in_args, out_args){
    // callback(error: nil, arg0: args[0] as A?, arg1: args[1] as B?, arg2: args[2] as C?);

    var call = "return callback(error: nil";

    _.for(out_args, function(i){
        call += ", outArg" + i + ": args[" + i + "] as " + out_arg_generic_type(i) + "?" ;
    });

    call += ");";

    return(call);
}

function make_method_body(in_args, out_args){
    var body = _.string_builder(); 
    body.in(4);

    body.add_line("{");
    body.in(4);

    make_outgoing_message(body, in_args, out_args);
    body.add_line("self.callEndpointGetArgs(outgoingMessage, { (error, args) in ");
    body.in(4);

    body.add_line("if(error != nil){");
    body.in(4);
    body.add_line(make_error_call(in_args, out_args));
    body.out(4);
    body.add_line("}");
    body.add_line();


    body.add_line("func errorOut(i: Int, e: AnyObject?){");
    body.in(4);
    
    body.add_line("let error = self.badSignatureError(i, e);");
    body.add_line(make_error_call(in_args, out_args));
    body.out(4);
    body.add_line("}");
    body.add_line();

    body.add_line("var args = args!;");
    body.add_line();

    _.for(out_args, function(i){
        body.add_line("if(args.count <= " + i + "){ args.append(nil); }");
        body.add_line("if(args[" + i + "] != nil && ((args[" + i + "] as? " + out_arg_generic_type(i) + ") == nil)){");
        body.in(4);
        body.add_line("return errorOut(" + i + ", args[" + i + "]);");
        body.out(4);
        body.add_line("}");
    });

    body.add_line(make_callback_call(in_args, out_args));
    body.out(4);
    body.add_line("});");
    body.out(4);
    body.add_line("}");

    return(body.string());
}

/*
function test(){
    _.p(make_method_signature(3, 3));
    _.p(make_method(3, 3));
}
*/

function make_method(in_args, out_args){

    var method = "    " + make_method_signature(in_args, out_args);

    method += make_method_body(in_args, out_args);

    return(method);
}

function make_methods_hash(args_in, args_out){

    var methods = [];

    _.for(args_in + 1, function(i){
        _.for(args_out + 1, function(o){
            methods.push(make_method(i, o));
        });
    });

    return({ methods: methods });
}

function make_client(args_in, args_out, out_path){

    var hash = make_methods_hash(args_in, args_out);

    var base_file = _.fs.readFile.sync("./lib/DryApiClientBase.swift");

    var client_file = _.fs.renderFile.sync("./templates/DryApiClient.swift.hb", hash);

    var client_code = base_file + "\n" + client_file;

    _.fs.writeFile.sync(out_path, client_code);
}

function main(){
    make_client(10, 10, "./lib/DryApiClient.swift");
    make_client(3, 3, "./lib/DryApiClient.small.swift");
}

main();
// test();
