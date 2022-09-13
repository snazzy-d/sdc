module driver.sdfmt;

int main(string[] args) {
	bool dbg = false;
	bool inPlace = false;

	import std.getopt;
	try {
		auto help_info = getopt(
			// sdfmt off
			args, std.getopt.config.caseSensitive,
			"debug", "Enable debug",          &dbg,
			"i",     "Format files in place", &inPlace,
			// sdfmt on
		);

		if (help_info.helpWanted || args.length == 1) {
			import std.stdio;
			writeln("The Snazzy D Compiler - Code Formatter");
			writeln("Usage: sdfmt [options] file.d");
			writeln("Options:");

			foreach (option; help_info.options) {
				writefln(
					"  %-16s %s",
					// bug : optShort is empty if there is no long version
					option.optShort.length
						? option.optShort
						: (option.optLong.length == 3)
							? option.optLong[1 .. $]
							: option.optLong,
					option.help
				);
			}

			return 0;
		}
	} catch (GetOptException ex) {
		import std.stdio;
		writefln("%s", ex.msg);
		writeln("Please use -h to get a list of valid options.");
		return 1;
	}

	auto files = args[1 .. $];

	import source.context;
	auto context = new Context();

	foreach (filename; files) {
		import format.config;
		Config conf;

		import config.build;
		conf.buildLocalConfig("sdfmt", context, filename);

		import source.location;
		auto base = context.registerFile(Location.init, filename, "");

		import format.parser;
		auto chunks = Parser(base, context).parse();

		if (dbg) {
			import std.stdio;
			writeln(chunks);
		}

		import format.writer;
		auto o = chunks.write(conf);

		if (inPlace) {
			// TODO: Only write if the file changed.
			import std.file;
			filename.write(o);
		} else {
			import std.stdio;
			write(o);
		}
	}

	return 0;
}
