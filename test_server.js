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

