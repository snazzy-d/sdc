module sdc.tester;

string testDir = "tests";
string testRegEx = "test*.d";
string exclude = "*import*.d";

version (No_Race) 
{} else {
import std.parallelism;
}

int main() {
	import sdc.conf;
	auto t = Tester(buildConf(), testDir, testRegEx, exclude);
	t.runTests();
	return 0;
}

struct Tester {
	string[] versions;
	string testDir;
	string testRegEx;
	string exclude;
	import util.json;
	JSON conf;
	
	import atomicarray;
	import sdc.sdc;
	import util.terminal;
	import std.string;
	import std.stdio;
	import std.file;
	import std.conv;
	
	this(JSON conf, string testDir, 
		string testRegEx, string exculde,
		string[] versions = [],
	) {
		
		this.conf = conf;
		this.versions = versions;
		this.testDir = testDir;
		this.testRegEx = testRegEx;
		this.exclude = exclude;
		this.conf["includePath"] ~= testDir;
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
	}
	
	struct Result {
		uint testNumber;
		bool hasPassed;
		bool compiles;
	}
	/// returns true if there are no regressions
	/// false otherwise
	bool runTests() {
		immutable Test[] tests = readTests();
		AtomicArray!Result results;
		
		//results._data.reserve(cast(uint)tests.length);
		version (No_Race) {
			auto _tests = tests;
		} else {
			auto _tests = parallel(tests);
		}

		foreach (id, test;_tests) {
			writeln("compling: ", test.name);
			auto sdc = new SDC(test.name, conf, 0);

			auto r = atomicValue(Result(test.number, false, true), cast(uint)id); 
			try {
				sdc.compileBuffer(test.code.ptr, test.code.length,  test.name.ptr, test.name.length);
				foreach (i,dep;test.deps) { 
					string depName = test.name ~ "_import" ~ to!string(i);
					sdc.compileBuffer(dep.ptr, dep.length, depName.ptr, depName.length);
					sdc.outputObj(depName ~ ".o");
				}
			} catch (Throwable t) {
				r.compiles = false;
				writeln("Compile Error:", t.msg);
			}

			if (r.compiles) {
				try {
					sdc.buildMain();
					sdc.outputObj(test.name ~ ".o");
					sdc.linkExecutable(test.name ~ ".o", test.name ~ ".exe"); 
				} catch (Throwable t) {
					writeln("Link Error:", t.msg);
				}
			}

			if (exists(test.name ~ ".exe")) {
				import std.process;
				r.hasPassed = std.process.spawnProcess("./" ~ test.name ~ ".exe").wait == test.retval;
			} else {
				if (!test.compiles) r.hasPassed = true;
			}
			
			results ~= r;
			writeln(test.name , " done");
		}
		
		if(results.length != tests.length) {assert(0);}
		
		AtomicArray!string regressions;
		AtomicArray!string improvements;
		
		version(No_Race) {
			auto _results = results._data;
		} else {
			auto _results = parallel(results._data);
		}

		foreach (id,r;_results) {
			auto i = r.testNumber;
			if (tests[i].has_passed && !r.hasPassed) {
				regressions ~= atomicValue(tests[i].name, cast(uint)id);
			} else if (!tests[i].has_passed && r.hasPassed) {
				improvements ~= atomicValue(tests[i].name, cast(uint)id);
			}
		}

		if (regressions.length) {
			stdout.writeColouredText( ConsoleColour.Red, "Tests regressed: ", regressions, "\n");
		} 
		if (improvements.length) { 
			stdout.writeColouredText(ConsoleColour.Green, "Tests improved: ", improvements, "\n");
		}

		return cast(bool) regressions.length;
	}
	
	immutable(Test[]) readTests () {
		import std.path;

		static bool yn2bool (string yn) {
			if (yn == "yes"|| yn == "true") return true;
			else if (yn == "no"|| yn ==  "false") return false;
			else assert(0,"Malformed Input "~yn~" has to be yes or no");
		}
		
		shared int testNumber;
		string name;
		string filename;
		AtomicArray!Test tests;
		
		version (No_Race) {
			auto testFiles = dirEntries(testDir, testRegEx ,SpanMode.depth);
		} else {
			auto testFiles = dirEntries(testDir, testRegEx ,SpanMode.depth).parallel;
		}

		FileLoop : foreach(testFile;testFiles) {
			if (testFile.name.globMatch(exclude)) continue FileLoop;
			auto t = atomicValue(Test.init, testNumber);
			t.name = baseName(testFile);
			filename = testFile;
			if (!exists(filename)) break;
			
			t.number = testNumber;

			auto f = File(filename, "r");
			
			scope (exit) f.close();
			
			foreach (line; f.byLine) {
				if (line.length < 3 || line[0 .. 3] != "//T") {
					t.code ~= to!string(line)~"\n";
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
						auto df = File(testDir ~ std.path.dirSeparator ~ val,"r");
						string dep;
						foreach(l;df.byLine) {
							dep~=to!string(l)~"\n";
						}
						t.deps ~= dep ~ '\0';
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
			t.code ~= '\0';
			tests ~= t;
			core.atomic.atomicOp!"+="(testNumber, 1);
		} 
		assert(tests.length == testNumber);
		return cast(immutable(Test[])) tests._data;
	}
	
}
