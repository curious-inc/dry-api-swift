# Documentation TODO
*write documentation*
*whitelisting errors*
*make sure context function is correct*
*local clients (include maxSockets info)*
*require('http').globalAgent.maxSockets = 200;*
*wire format changed*


# dry: api swift client

## Installing

To install: 

    npm install dry-api-swift


## Introduction

This package provides an api client for dry framework based apis. Dry api's are elegant to write, and feature role based, declaritive security and validations. 

They are transport agnostic, and protocol agnostic. You can run them REST over HTTP, you can run RPC over TCP or HTTP.

This runs RPC over HTTP.

## The look

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
    if(err){ throw(err); }

    println(name_message_response); // "Hello Kendrick."
    println(age_message_response); // "You're 30 years old."

});


```


## License

See the LICENSE file in the root of the repo for license information.

