module sdc.conf;

import util.json;

auto buildConf() {
	auto conf = parseJSON(`{
		"includePath": ["@SDCPATH@/../libs", "."],
		"libPath": ["@SDCPATH@/../lib"],
	}`);
	
	// System wide configuration
	conf.extends(getConf("/etc/sdc.conf"));
	
	// User wide configuration.
	import std.process;
	if(auto home = environment.get("HOME", "")) {
		conf.extends(getConf(home ~ "/.sdc/sdc.conf"));
	}
	
	// SDC's folder.
	import std.file;
	import std.array;
	auto path = thisExePath.split('/');
	path[$ - 1] = "sdc.conf";
	
	conf.extends(getConf(path.join("/")));
	
	// Current folder.
	conf.extends(getConf("sdc.conf"));
	
	return conf;
}

auto getConf(string filename) {
	import std.file;
	if(!exists(filename)) {
		return JSON(null);
	}
	
	return parseJSON(cast(string) read(filename));
}

void extends(ref JSON base, JSON add) {
	foreach(string key, value; add) {
		base[key] = value;
	}
}

