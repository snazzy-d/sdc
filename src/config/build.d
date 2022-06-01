module config.build;

import source.context;

import config.value;

auto parseAndExtendIfExist(C)(ref C config, Context context, string filename) {
	import std.file;
	if (!exists(filename)) {
		return;
	}

	return config.parseAndExtend(context, filename);
}

auto parseAndExtend(C)(ref C config, Context context, string filename) {
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
	// SDC's folder.
	import std.file, std.path;
	config
		.parseAndExtendIfExist(context, thisExePath.dirName().buildPath(name));

	// System wide configuration.
	config.parseAndExtendIfExist(context, "/etc".buildPath(name));

	// User wide configuration.
	import std.process;
	if (auto home = environment.get("HOME", "")) {
		config.parseAndExtendIfExist(context, home.buildPath('.' ~ name));
	}
}

auto buildLocalConfig(C)(ref C config, string name, Context context,
                         string filename) {
	// Prepend a dot once and for all.
	name = '.' ~ name;

	import std.path;
	filename = filename.absolutePath() ~ name;
	auto dir = filename;

	string[] files;

	while (true) {
		import std.file;
		if (exists(filename)) {
			files ~= filename;
		}

		auto parentDir = dir.dirName();
		if (parentDir == dir) {
			// We can't go any further.
			break;
		}

		dir = parentDir;
		filename = dir.buildPath(name);
	}

	import std.range;
	foreach (file; files.retro()) {
		config.parseAndExtend(context, file);
	}
}
