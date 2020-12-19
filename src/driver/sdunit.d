module driver.dsunit;

immutable string[2] ResultStr = ["FAIL", "PASS"];

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
		
		import d.ir.symbol;
		Module m = null;
		
		bool returnCode = 0;
		auto results = c.runUnittests();
		if (results.length == 0) {
			import std.stdio;
			writeln("No test to run");
			return 0;
		}
		
		import std.stdio;
		write("Test results:");
		
		foreach (r; results) {
			if (!r.pass) {
				returnCode = 1;
			}
			
			auto testModule = r.test.getModule();
			if (m != testModule) {
				m = testModule;
				
				import d.context.context;
				static void printModule(P)(Context c, P p) {
					if (p.parent is null) {
						import std.stdio;
						write("\nModule ", p.toString(c));
						return;
					}
					
					printModule(c, p.parent);
					
					import std.stdio;
					write(".", p.toString(c));
					
					static if(is(P : Module)) {
						writeln(":");
					}
				}
				
				printModule(c.context, m);
			}
			
			auto name = r.test.name.toString(c.context);
			
			import std.stdio;
			writefln("\t%-24s %s", name, ResultStr[r.pass]);
		}
		
		return returnCode;
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

	// This is unreachable, but dmd can't figure this out.
	assert(0);
}
