module sdc.config;

struct Config {
	string[] includePaths;
	string[] linkerPaths;
	uint optLevel;
	bool enableUnittest;
}

import source.context;

import config.value;

auto buildBaseConfig(Context context) {
	Config config;
	
	// After user supplied path, always check current directory.
	config.includePaths ~= ".";
	
	// System wide configuration.
	config.extends(context.getConf("/etc/sdc.conf"));
	
	// User wide configuration.
	import std.process;
	if (auto home = environment.get("HOME", "")) {
		config.extends(context.getConf(home ~ "/.sdc/sdc.conf"));
	}
	
	// SDC's folder.
	import std.file, std.array;
	auto path = thisExePath.split('/');
	path[$ - 1] = "sdc.conf";
	
	config.extends(context.getConf(path.join("/")));
	
	return config;
}

auto getConf(Context context, string filename) {
	import std.file;
	if (!exists(filename)) {
		return Value(null);
	}
	
	import source.location;
	auto base = context.registerFile(Location.init, filename, "");
	
	import source.jsonlexer;
	auto lexer = lex(base, context);
	
	import config.jsonparser;
	return lexer.parseJSON();
}

void extends(ref Config config, Value add) {
	if (add == null) {
		return;
	}
	
	if (auto ip = "includePaths" in add) {
		import std.algorithm, std.range;
		config.includePaths = ip.array
			.map!(i => i.str)
			.chain(config.includePaths)
			.array();
	}
	
	if (auto lp = "libPaths" in add) {
		import std.algorithm, std.range;
		config.linkerPaths = lp.array
			.map!(i => i.str)
			.chain(config.linkerPaths)
			.array();
	}
}
