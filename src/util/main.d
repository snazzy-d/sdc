module driver.main;

int runMain(alias run)(string[] args) {
	version(DigitalMars) {
		version(linux) {
			import etc.linux.memoryerror;
			// druntime not containe the necessary symbol.
			// registerMemoryErrorHandler();
		}
	}

	import source.context;
	auto context = new Context();

	bool dbg = false;

	import std.getopt, source.exception;
	try {
		auto help_info = getopt(
			// sdfmt off
			args,
			std.getopt.config.caseSensitive,
			std.getopt.config.passThrough,
			"debug", "Enable debug", &dbg,
			// sdfmt on
		);

		return run(context, args);
	} catch (GetOptException ex) {
		import std.stdio;
		writefln("%s", ex.msg);
		writeln("Please use -h to get a list of valid options.");
		return 1;
	} catch (CompileException e) {
		import util.terminal;
		outputCaretDiagnostics(e.getFullLocation(context), e.msg);

		// Rethrow in debug, so we have the stack trace.
		if (dbg) {
			throw e;
		}

		return 1;
	}

	// This is unreachable, but dmd can't figure this out.
	assert(0);
}
