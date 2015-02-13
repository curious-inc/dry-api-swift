#!/usr/bin/env node

"use strict";

// _.log.level("debug");

var _ = require('dry-underscore');
var test_server = require('dry-api').test_server;

var config = _.extend(test_server.config, {
    port: 9998,
    url: "/api",
    host: "http://localhost"
});

var api_manager = test_server.api_manager;
var api_hash = api_manager.hash(true);

// var client = new dry_api.client(config.host + ":" + config.port + config.url);

// var eq = _.test.eq;
// var ok = _.test.ok;

test_server.start_server(function(){
    console.log("server running on port: " + config.port);
    console.log("ctrl-c to exit");
});

/*
test("client.call echo", function(done){
    client.call("test.echo", [1, 2, 3], function(err, one, two, three){
        if(err){ throw(err); }
        eq(this.access_token, null);
        eq(err, null);
        eq(one, 1);
        eq(two, 2);
        eq(three, 3);

        done();
    });
});

test("client.call named", function(done){
    client.call("test.named", { one: 1, two: 2, three: 3 }, function(err, one, two, three){
        if(err){ throw(err); }
        eq(this.access_token, null);
        ok(!err);
        eq(one, 1);
        eq(two, 2);
        eq(three, 3);

        done();
    });
});

test("client.call named_back", function(done){
    client.call("test.named_back", { one: 1, two: 2, three: 3 }, function(err, one, two, three){
        if(err){ throw(err); }
        eq(this.access_token, null);
        ok(!err);
        eq(one, 1);
        eq(two, 2);
        eq(three, 3);

        done();
    });
});

test("client.call roles public", function(done){
    client.access_token(null).call("test.roles", [], function(err, api_role, roles){
        if(err){ throw(err); }
        eq(this.access_token, null);
        eq(api_role, "public");
        eq(roles, []);

        done();
    });
});

test("client.call roles user", function(done){
    client.access_token("user_token").call("test.roles", [], function(err, api_role, roles){
        if(err){ throw(err); }
        eq(this.access_token, "user_token");
        eq(api_role, "user");
        eq(roles, ["user"]);

        done();
    });
});

test("client.call roles admin", function(done){
    client.access_token("admin_token").call("test.roles", [], function(err, api_role, roles){
        if(err){ throw(err); }
        eq(this.access_token, "admin_token");
        eq(api_role, "admin");
        eq(roles, ["user", "admin"]);

        done();
    });
});

test("smart_client roles admin", function(done){
    var smart_client = client.smart_client(api_hash);
    smart_client.access_token("admin_token").test().roles(function(err, api_role, roles){
        if(err){ throw(err); }
        eq(this.access_token, "admin_token");
        eq(api_role, "admin");
        eq(roles, ["user", "admin"]);

        done();
    });
});

test("smart_client echo", function(done){
    var smart_client = client.smart_client(api_hash);
    smart_client.access_token("admin_token").test().echo(1, 2, 4, function(err, one, two, four){
        if(err){ throw(err); }
        eq(this.access_token, "admin_token");
        eq(one, 1);
        eq(two, 2);
        eq(four, 4);

        done();
    });
});

test("smart_client echo nothing", function(done){
    var smart_client = client.smart_client(api_hash);
    smart_client.access_token("admin_token").test().echo(function(err){
        if(err){ throw(err); }
        eq(arguments.length, 1);
        done();
    });
});

*/

/*
test("smart_client write_code", function(done){
    var smart_client_code = client.smart_client_code(api_hash);
    _.fs.writeFile("./smart_client_code_test.js", smart_client_code, done);
});
*/
