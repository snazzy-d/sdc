module d.context;

struct Name {
private:
	uint id;
	
	this(uint id) {
		this.id = id;
	}
	
public:
	string toString(Context c) const {
		return c.names[id];
	}
	
	@property
	bool isReserved() const {
		return id < (Names.length - Prefill.length);
	}
	
	@property
	bool isDefined() const {
		return id != 0;
	}
}

final class Context {
private:
	string[] names;
	uint[string] lookups;
	
public:
	this() {
		names = Names;
		lookups = Lookups;
	}
	
	auto getName(string s) {
		if (auto id = s in lookups) {
			return Name(*id);
		}
		
		// Do not keep around slice of potentially large input.
		s = s.idup;
		
		auto id = lookups[s] = cast(uint) names.length;
		names ~= s;
		
		return Name(id);
	}
}

template BuiltinName(string name) {
	private enum id = Lookups.get(name, uint.max);
	
	static assert(id < uint.max, name ~ " is not a builtin name.");
	
	enum BuiltinName = Name(id);
}

private:

enum Reserved = ["__ctor", "__dtor", "__vtbl"];

enum Prefill = [
	// Linkages
	"C", "D", "C++",
	// Version
	"SDC", "D_LP64",
	// Generated
	"init", "sizeof", "length", "ptr",
	// Scope
	"exit", "success", "failure",
	// Main
	"main", "_Dmain",
	// Defined in object
	"object", "size_t", "ptrdiff_t", "string",
	"Object",
	"TypeInfo", "ClassInfo",
	"Throwable", "Exception", "Error",
	// Runtime
	"__sd_class_downcast",
];

auto getNames() {
	import d.lexer;
	
	auto identifiers = [""];
	foreach(k, _; getOperatorsMap()) {
		identifiers ~= k;
	}
	
	foreach(k, _; getKeywordsMap()) {
		identifiers ~= k;
	}
	
	return identifiers ~ Reserved ~ Prefill;
}

enum Names = getNames();

static assert(Names[0] == "");

auto getLookups() {
	uint[string] lookups;
	foreach(uint i, id; Names) {
		lookups[id] = i;
	}
	
	return lookups;
}

enum Lookups = getLookups();

