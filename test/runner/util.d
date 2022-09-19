module util;

bool getBool(string s) {
	return s == "yes";
}

int getInt(string s) {
	import std.conv;
	return parse!int(s);
}

int runUtility(U, string File = __FILE__)(auto ref U utility, string[] args) {
	Options options = parseArguements!File(utility, args);

	// Set the current working directory to the base of the repository.
	setcwd();

	auto result = utility.getTasks(args).runTasks(options);

	import std.stdio;
	writefln!"Summary: %s tests, %s pass%s, %s failure%s, %.2f%% pass rate, %s regressions, %s improvements."(
		result.count,
		result.passed,
		result.passed == 1 ? "" : "es",
		result.count - result.passed,
		(result.count - result.passed) == 1 ? "" : "s",
		100 * (double(result.passed) / result.count),
		result.regressions,
		result.improvments
	);

	if (options.waitOnExit) {
		write("Press any key to exit...");
		readln();
	}

	return result.regressions > 0 ? -1 : 0;
}

struct Options {
	size_t jobCount = 1;
	bool displayOnlyFailed = false;
	bool waitOnExit = false;
}

template GetOptArgsBuilder(R...) {
	template Build(Args...) {
		static if (Args.length == 0) {
			alias Build = R;
		} else {
			import std.meta;
			alias RR = Replace!(typeof(*Args[0]), Args[0], R);
			alias Build = GetOptArgsBuilder!RR.Build!(Args[1 .. $]);
		}
	}
}

Options parseArguements(string File, U)(ref U utility, ref string[] args) {
	alias ExtraArgsDef = U.ExtraArgs;

	import std.meta, std.traits;
	alias ExtraArgsTypes = Filter!(isType, ExtraArgsDef);
	ExtraArgsTypes extraArgs;

	// FIXME: sdfmt fails to parse that this is a pointer.
	alias ptrOf(T) = T*;
	alias ExtraArgsPtrTypes = staticMap!(ptrOf, ExtraArgsTypes);
	ExtraArgsPtrTypes extraArgsPtr;

	foreach (i, _; extraArgs) {
		extraArgsPtr[i] = &extraArgs[i];
	}

	alias GetOptArgs = GetOptArgsBuilder!ExtraArgsDef.Build!extraArgsPtr;

	Options options;

	version(linux) {
		import core.sys.posix.unistd;
		options.jobCount = sysconf(_SC_NPROCESSORS_ONLN);
	}

	import std.getopt;
	try {
		auto help_info = getopt(
			// sdfmt off
			args,
			GetOptArgs,
			"j", "Specifies the number of jobs (commands) to run simultaneously.", &options.jobCount,
			"only-failed", "Only display failed tests.", &options.displayOnlyFailed,
			"wait-on-exit", "Wait for user input before exiting.", &options.waitOnExit,
			// sdfmt on
		);

		if (help_info.helpWanted) {
			import std.stdio;
			writeln("The Snazzy D Compiler - ", U.Name);
			writeln("Usage: ", File, " [options]",
			        U.XtraDoc ? " [" ~ U.XtraDoc ~ "]" : "");
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

			import core.stdc.stdlib;
			exit(0);
		}
	} catch (GetOptException ex) {
		import std.stdio;
		writefln("%s", ex.msg);
		writeln("Please use -h to get a list of valid options.");

		import core.stdc.stdlib;
		exit(1);
	}

	import std.algorithm;
	options.jobCount = max(options.jobCount, options.jobCount - 1);

	utility.processArgs(extraArgs);
	return options;
}

struct Result {
	uint count = 0;
	uint passed = 0;
	uint regressions = 0;
	uint improvments = 0;
}

struct TestResult {
	string name;
	bool result;
	bool hasPassed;
}

Result runTasks(R)(R tasks, ref const Options options) {
	import std.concurrency;

	Result r;

	int running = 0;
	void waitForJob() {
		auto testResult = receiveOnly!TestResult();
		running--;

		bool regressed = !testResult.result && testResult.hasPassed;
		bool fixed = testResult.result && !testResult.hasPassed;

		r.passed += testResult.result;
		r.regressions += regressed;
		r.improvments += fixed;

		import std.stdio;
		if (testResult.result) {
			if (!options.displayOnlyFailed) {
				writef("%s: %s", testResult.name, "SUCCEEDED");
			}
		} else {
			writef("%s: %s", testResult.name, "FAILED");
		}

		if (fixed) {
			if (!options.displayOnlyFailed) {
				writeln(", FIXED");
			}
		} else if (regressed) {
			writeln(", REGRESSION");
		} else if ((options.displayOnlyFailed && !testResult.result)
			           || !options.displayOnlyFailed) {
			writeln();
		}
	}

	foreach (t; tasks) {
		alias Task = typeof(t);

		r.count++;
		running++;

		static void runTask(Task task, Tid managerTid) {
			try {
				managerTid.send(task.run());
			} catch (Exception e) {
				import std.stdio;
				stderr.writeln(e);

				// Make sure we send something back when we fail.
				managerTid.send(TestResult("", false, true));
			}
		}

		spawn(&runTask, t, thisTid);

		if (running >= options.jobCount) {
			waitForJob();
		}
	}

	// Wait for inflight jobs to finish
	while (running > 0) {
		waitForJob();
	}

	return r;
}

string getAbsolutePath(string path) {
	if (path == "") {
		return path;
	}

	import std.path, std.array;
	return path.asAbsolutePath().asNormalizedPath().array();
}

void setcwd() {
	// Get this file's folder.
	import std.path, std.array;
	string dirname =
		__FILE__.asAbsolutePath().asNormalizedPath().array().dirName();

	// Switch to this file's folder.
	import std.file;
	chdir(dirname);

	// Get to the root of the repository.
	import std.process;
	auto result = execute(["git", "rev-parse", "--show-toplevel"]);

	import std.exception;
	enforce(result.status == 0, "Failed to find the root of this repository");

	import std.string;
	string base = result.output.strip();
	chdir(base);
}
