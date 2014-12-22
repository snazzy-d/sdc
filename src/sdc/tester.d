module sdc.tester;

import sdc.terminal;
import d.location;

private final class StringSource : Source {

	string _name;
	immutable string[] _packages;
	this(in string content,in string name, immutable string[] _packages=[]) {
		_name = name;
		this._packages = _packages;
		assert(name[$-2 .. $] != ".d","stringSources don't get the .d extention");
		super(content ~ '\0');
	}
	override string format(const Location location) const {
		import std.conv;
		return _name ~ ':' ~ to!string(location.line);
	}
	@property
	override string filename() const {
		return _name;
	}
	@property
	const(string[]) packages() const {
		return _packages;
	}
}



struct Tester {
	import util.json;

	JSON conf;
	string[] versions;

	bool hasRun;

	import sdc.sdc;

	import std.string;
	import std.stdio;
	import std.file;
	import std.conv;

	this (JSON conf) {
		this.conf = conf;
	}

	struct Test {
	public:
		string name;
		uint number;
		bool compiles;
		bool has_passed;
		int retval;
		string[] deps;
		string code;

		Location[] failureLocations;
	}

	struct Result {
		uint testNumber;
		bool hasPassed;
		bool compiles;
	}

	bool runTests() {
		immutable Test[] tests = readTests();
		Result[] results;
		foreach (test;tests) {
		
			auto sdc = new SDC(test.name ~ ".d", conf, 0);
			sdc.includePath ~= "tests";
			auto r = Result(test.number, false, true);
			 
			try {
			sdc.compile(new StringSource(test.code, test.name), [sdc.context.getName(test.name)]);
				foreach (i,dep;test.deps) {
					sdc.compile(new StringSource(dep, test.name ~ "_import"));
				}
			} catch (Throwable t) {
				r.compiles = false;
				writeln(t.msg);
			}

			try {
				sdc.buildMain();
				sdc.codeGen(test.name ~ ".o", test.name ~ ".exe"); 
			} catch (Throwable t) {
				writeln(t.msg);
			}

			if (exists(test.name ~ ".exe")) {
				import std.process;
				r.hasPassed = std.process.spawnProcess("./" ~ test.name ~ ".exe").wait == test.retval;
			} else {
				if (!test.compiles) r.hasPassed = true;
			}

			results ~= r;
		}

		assert(results.length == tests.length);

		ulong[] regressions;
		ulong[] improvements;
		foreach (i,r;results) {
			if (tests[i].has_passed && !r.hasPassed) {
				regressions ~= i;
			} else if (!tests[i].has_passed && r.hasPassed) {
				improvements ~= i;
			}
		}
		if (regressions.length) {
			writeColouredText(stdout, ConsoleColour.Red, {writeln("Tests regressed: ", regressions);});
		} 
		if (improvements.length) { 
			writeColouredText(stdout, ConsoleColour.Green, {writeln("Tests improved: ", improvements);});
		}
		return cast(bool) regressions.length;
	}

	immutable(Test[]) readTests () {

		static bool yn2bool (string yn) {
			if (yn == "yes"|| yn == "true") return true;
			else if (yn == "no"|| yn ==  "false") return false;
			else assert(0,"Malformed Input "~yn~" has to be yes or no");
		}

		int testNumber;
		string dir = "tests";
		string name;
		string filename;
		Test[] tests;
		while (true) {
			Test t;
			t.name = format("test%04s", testNumber);
			filename = dir ~ std.path.dirSeparator ~ t.name ~ ".d";
			if (!exists(filename)) break;

			t.number = testNumber;
			if (t.number == 42) {testNumber++; continue;} //FIXME omit test42 until I have found how to fix the tester!

			auto f = File(filename, "r");
			scope (exit) f.close();
			
			foreach (line; f.byLine) {
				if (line.length < 3 || line[0 .. 3] != "//T") {
					t.code~=to!string(line)~"\n";
					continue;
				}
				auto words = split(line);
				if (words.length != 2) {
					stderr.writefln("%s: malformed test.", filename);
				}
				auto set = split(words[1], ":");
				if (set.length < 2) {
					throw new Exception(filename ~ ": malfotmed test");
				}
				auto var = set[0].idup;
				auto val = set[1].idup;
				
				switch (var) {
					case "compiles":
						t.compiles=yn2bool(val);
						break;
					case "retval":
						t.retval = parse!int(val); 
						break;
					case "dependency":
						auto df = File(dir ~ std.path.dirSeparator ~ val,"r");
						string dep;
						foreach(l;df.byLine) {
							dep~=to!string(l)~"\n";
						}
						t.deps ~= dep;
						break;
					case "has-passed":
						t.has_passed = yn2bool(val);
						break;
						// case "desc" :
						//    t.desc = val~cast(immutable)(words[2 .. $]).join(" ");
						//    break;
					default:
						throw new Exception("Unkown command");
				}
			}
			tests ~= t;
			testNumber++;
		} 

		return cast(immutable(Test[])) tests;
	}

}

