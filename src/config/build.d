module config.build;

import source.context;

import config.value;

auto parseAndExtend(C)(ref C config, Context context, string filename) {
	import std.file;
	if (!exists(filename)) {
		return;
	}
	
	import source.location;
	auto base = context.registerFile(Location.init, filename, "");
	
	import source.jsonlexer;
	auto lexer = lex(base, context);
	
	// Workaround for https://issues.dlang.org/show_bug.cgi?id=22482
	auto cfg = &config;
	
	import config.jsonparser;
	return cfg.extends(lexer.parseJSON());
}

auto buildGlobalConfig(C)(ref C config, string name, Context context) {
	// System wide configuration.
	config.parseAndExtend(context, "/etc".buildPath(name));
	
	// User wide configuration.
	import std.process;
	if (auto home = environment.get("HOME", "")) {
		config.parseAndExtend(context, home.buildPath('.' ~ name));
	}
	
	// SDC's folder.
	import std.file, std.path;
	auto path = thisExePath.dirName().buildPath(name);
	config.parseAndExtend(context, path);
}
