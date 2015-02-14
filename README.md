
# dry: api swift client

## Installing

To install: 

    Add the file `lib/DryApiClient.swift` to your XCode project.


## Introduction

This package provides an api client for dry framework based apis. Dry api's are elegant to write, and feature role based, declaritive security and validations. 

They are transport agnostic, and protocol agnostic. You can run them REST over HTTP, you can run RPC over TCP or HTTP.

This runs RPC over HTTP.

## The Look

```
// server side

var api = api_manager.api("example_api", true);

api.public("hello_messages", function(callback, name, age){

    var name_message = "Hello " + name + ".";
    var age_message =  "You're " + age + " years old.";

    callback(null,   "You're " + age + " years old.");

});

// node or browser side

client.example_api().hello_messages("Kendrick", 30, function(err, name_message_response, age_message_response){
    if(err){ throw(err); }

    console.log(name_message_response); // "Hello Kendrick."
    console.log(age_message_response); // "You're 30 years old."

});

// iOS side

client.call("example_api.hello_messages", "Kendrick", 30, { (error, nameMessageResponse: String?, ageMessageResponse: String?) in
    if(err){ return println("error: \(err)"); }

    println(name_message_response); // "Hello Kendrick."
    println(age_message_response); // "You're 30 years old."

});

```

## Usage

Until I add more to the docs, take a look at the tests. They show most of the functionality.

## Types

The examples in this section assumes an "echo" api function that turns around whatever values you send it. The source code for it is below, in the section "Echo Source Code"

The api client is generated from a script, the client supports up to 10 sent parameters, and 10 callback parameters. If you need more, put up a GitHub issue. It's an easy fix.

This works using generics, so you just define the types you expect, and the client will try to cooerce the values from the server into those types.
If it doesn't work, you'll get an error passed to your callback.

If you're accepting dictionaries, or arrays, they need to be NSDictionary? and NSArray? types. Swift's type system is terrible, I would love to use Dictionary, and Array.

```
client.call("example_api.echo", [ "name": "Kendrick" ], ["zero", "one"], { (error, hash: NSDictionary?, array: NSArray?) in
    println("\(hash)"); // ["name":  "Kendrick"]
    println("\(array)"); // ["zero", "one"]
});

```

You need to accept optional types in the callback, because if the server doesn't send a value for that parameter, you'll get a `nil`.

If you need to send a `null` value use `NSNull()` or `client.null`, which is just a convenience declaration of `NSNull`.

```
client.call("example_api.echo", NSNull(), client.null, { (error, arg0: String?, arg1: String?) in
    println("\(arg0)"); // nil
    println("\(arg1)"); // nil
});

```

## Echo Source Code
```
// server side

var api = api_manager.api("example_api", true);

api.public("echo", function(callback, a, b, c, d){

    return callback(null, a, b, c, d);

});
```


## Documentation TODO
- write more documentation

## License

See the LICENSE file in the root of the repo for license information.

