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

	import std.getopt, source.exception;
	try {
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
		debug {
			throw e;
		} else {
			return 1;
		}
	}

	// This is unreachable, but dmd can't figure this out.
	assert(0);
}
