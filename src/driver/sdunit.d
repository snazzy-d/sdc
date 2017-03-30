module driver.dsunit;

int main(string[] args) {
	import d.context.config;
	Config conf;
	conf.enableUnittest = true;
	
	import std.getopt;
	auto help_info = getopt(
		args, std.getopt.config.caseSensitive,
		"I",         "Include path",        &conf.includePaths,
		"O",         "Optimization level",  &conf.optLevel,
	);
	
	if (help_info.helpWanted || args.length == 1) {
		import std.stdio;
		writeln("The Stupid D Compiler - Unit test JIT");
		writeln("Usage: sdunit <options> file.d");
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
	
	// Cannot call the variable "sdc" or DMD complains about name clash
	// with the sdc package from the import.
	import sdc.sdc, sdc.conf;
	auto c = new SDC(files[0], buildConf(), conf);
	
	import d.exception;
	try {
		foreach (file; files) {
			c.compile(file);
		}
		
		c.runUnittests();
		
		return 0;
	} catch(CompileException e) {
		import util.terminal;
		outputCaretDiagnostics(e.getFullLocation(c.context), e.msg);
		
		// Rethrow in debug, so we have the stack trace.
		debug {
			throw e;
		} else {
			return 1;
		}
	}
}
