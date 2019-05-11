// Hello!
module driver.sdfmt;

int main(string[] args) {
	import d.context.config;
	Config conf;
	
	bool dbg = false;
	
	import std.getopt;
	auto help_info = getopt(
		args, std.getopt.config.caseSensitive,
		"debug",     "Include path",        &dbg,
	);
	
	if (help_info.helpWanted || args.length == 1) {
		import std.stdio;
		writeln("The Snazzy D Compiler - Code Formatter");
		writeln("Usage: sdfmt <options> file.d");
		writeln("Options:");
		
		foreach (option; help_info.options) {
			writefln(
				"  %-12s %s",
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
	
	auto files = args[1 .. $];
	
	import d.context;
	auto context = new Context(conf);
	
	foreach (filename; files) {
		import d.context.location;
	    auto base = context.registerFile(Location.init, filename, "");
		
		import d.lexer;
		auto l = lex(base, context).withComments();
		
		import sdc.format.parser;
		auto chunks = Parser(context, l).parse();
		
		import sdc.format.writter;
		auto o = Writter().write(chunks);
		
		if (dbg) {
			import std.stdio;
			writeln(chunks);
		}
		
		import std.stdio;
		writeln(o);
	}
	
	return 0;
}
