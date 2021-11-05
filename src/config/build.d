module config.build;

import source.context;

import config.value;

auto buildConfigFromFile(Context context, string filename) {
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

auto buildBaseConfig(C)(ref C config, string name, Context context) {
	// System wide configuration.
	config.extends(context.buildConfigFromFile("/etc/" ~ name));
	
	// User wide configuration.
	import std.process;
	if (auto home = environment.get("HOME", "")) {
		config.extends(context.buildConfigFromFile(home ~ "/." ~ name));
	}
	
	// SDC's folder.
	import std.file, std.array;
	auto path = thisExePath.split('/');
	path[$ - 1] = name;
	
	config.extends(context.buildConfigFromFile(path.join("/")));
	return config;
}
