module config.value;

import std.traits;

enum isPrimitiveValue(T) = is(T : typeof(null)) || is(T : bool)
	|| is(T : string) || isIntegral!T || isFloatingPoint!T;

enum isValue(T) = is(T : const(Value)) || isPrimitiveValue!T || isArrayValue!T
	|| isObjectValue!T || isMapValue!T;

enum isArrayValue(X) = false;
enum isArrayValue(A : E[], E) = isValue!E;

enum isObjectValue(X) = false;
enum isObjectValue(A : E[string], E) = isValue!E;

enum isMapValue(X) = false;
enum isMapValue(A : V[K], K, V) = !isObjectValue!A && isValue!K && isValue!V;

unittest {
	import std.meta;
	alias PrimitiveTypes = AliasSeq!(typeof(null), bool, byte, ubyte, short,
	                                 ushort, long, ulong, string);

	foreach (T; PrimitiveTypes) {
		assert(isValue!T);
		assert(isPrimitiveValue!T);
		assert(!isArrayValue!T);
		assert(!isObjectValue!T);
		assert(!isMapValue!T);

		alias A = T[];
		assert(isValue!A);
		assert(!isPrimitiveValue!A);
		assert(isArrayValue!A);
		assert(!isObjectValue!A);
		assert(!isMapValue!A);

		alias O = T[string];
		assert(isValue!O);
		assert(!isPrimitiveValue!O);
		assert(!isArrayValue!O);
		assert(isObjectValue!O);
		assert(!isMapValue!O);

		alias M = T[O];
		assert(isValue!M);
		assert(!isPrimitiveValue!M);
		assert(!isArrayValue!M);
		assert(!isObjectValue!M);
		assert(isMapValue!M);

		alias MM = M[M];
		assert(isValue!MM);
		assert(!isPrimitiveValue!MM);
		assert(!isArrayValue!MM);
		assert(!isObjectValue!MM);
		assert(isMapValue!MM);

		alias AA = A[];
		assert(isValue!AA);
		assert(!isPrimitiveValue!AA);
		assert(isArrayValue!AA);
		assert(!isObjectValue!AA);
		assert(!isMapValue!AA);

		alias AO = A[string];
		assert(isValue!AO);
		assert(!isPrimitiveValue!AO);
		assert(!isArrayValue!AO);
		assert(isObjectValue!AO);
		assert(!isMapValue!AO);

		alias OA = O[];
		assert(isValue!OA);
		assert(!isPrimitiveValue!OA);
		assert(isArrayValue!OA);
		assert(!isObjectValue!OA);
		assert(!isMapValue!OA);

		alias OO = O[string];
		assert(isValue!OO);
		assert(!isPrimitiveValue!OO);
		assert(!isArrayValue!OO);
		assert(isObjectValue!OO);
		assert(!isMapValue!OO);
	}
}

struct Value {
	enum Kind : byte {
		Null,
		Boolean,
		Integer,
		Floating,
		String,
		Array,
		Object,
		Map,
	}

private:
	Kind _kind;

	union {
		bool _boolean;
		long _integer;
		double _floating;
		string _str;
		Value[] _array;
		Value[string] _obj;
		Value[Value] _map;
	}

public:
	this(T)(T t) {
		this = t;
	}

	@property
	Kind kind() const nothrow {
		return _kind;
	}

	@property
	bool boolean() const nothrow in {
		assert(kind == Kind.Boolean);
	} do {
		return _boolean;
	}

	@property
	long integer() const nothrow in {
		assert(kind == Kind.Integer);
	} do {
		return _integer;
	}

	@property
	double floating() const nothrow in {
		assert(kind == Kind.Floating);
	} do {
		return _floating;
	}

	@property
	string str() const nothrow in {
		assert(kind == Kind.String);
	} do {
		return _str;
	}

	@property
	inout(Value)[] array() inout nothrow in {
		assert(kind == Kind.Array);
	} do {
		return _array;
	}

	@property
	inout(Value[string]) obj() inout nothrow in {
		assert(kind == Kind.Object);
	} do {
		return _obj;
	}

	@property
	inout(Value[Value]) map() inout nothrow in {
		assert(kind == Kind.Map);
	} do {
		return _map;
	}

	@property
	size_t length() const nothrow in {
		assert(kind == Kind.String || kind == Kind.Array || kind == Kind.Object
			|| kind == Kind.Map);
	} do {
		switch (kind) with (Kind) {
			case String:
				return str.length;
			case Array:
				return array.length;
			case Object:
				return obj.length;
			case Map:
				return map.length;
			default:
				assert(0);
		}
	}

	/**
	 * Map and Object features
	 */
	inout(Value)* opBinaryRight(string op : "in")(string key) inout in {
		assert(kind == Kind.Object || kind == Kind.Map);
	} do {
		return kind == Kind.Map ? Value(key) in map : key in obj;
	}

	/**
	 * Misc
	 */
	string toString() const {
		return this.visit!(function string(v) {
			alias T = typeof(v);
			static if (is(T : typeof(null))) {
				return "null";
			} else static if (is(T == bool)) {
				return v ? "true" : "false";
			} else static if (is(T == string)) {
				// This is retarded, but I can't find another way to do it.
				import std.conv;
				return to!string([v])[1 .. $ - 1];
			} else {
				import std.conv;
				return to!string(v);
			}
		})();
	}

	@trusted
	size_t toHash() const nothrow {
		return
			this.visit!(x => is(typeof(x) : typeof(null)) ? -1 : hashOf(x))();
	}

	/**
	 * Assignement
	 */
	Value opAssign()(typeof(null) nothing) {
		_kind = Kind.Null;
		_str = null;
		return this;
	}

	Value opAssign(B : bool)(B b) {
		_kind = Kind.Boolean;
		_boolean = b;
		return this;
	}

	Value opAssign(I : long)(I i) {
		_kind = Kind.Integer;
		_integer = i;
		return this;
	}

	Value opAssign(F : double)(F f) {
		_kind = Kind.Floating;
		_floating = f;
		return this;
	}

	Value opAssign(S : string)(S s) {
		_kind = Kind.String;
		_str = s;
		return this;
	}

	Value opAssign(A)(A a) if (isArrayValue!A) {
		_kind = Kind.Array;
		_array = [];
		_array.reserve(a.length);

		foreach (ref e; a) {
			_array ~= Value(e);
		}

		return this;
	}

	Value opAssign(O)(O o) if (isObjectValue!O) {
		_kind = Kind.Object;
		_obj = null;

		foreach (k, ref e; o) {
			_obj[k] = Value(e);
		}

		return this;
	}

	Value opAssign(M)(M m) if (isMapValue!M) {
		_kind = Kind.Map;
		_map = null;

		foreach (ref k, ref e; m) {
			_map[Value(k)] = Value(e);
		}

		return this;
	}

	/**
	 * Equality
	 */
	bool opEquals(const ref Value rhs) const {
		return this.visit!((x, const ref Value rhs) => rhs == x)(rhs);
	}

	bool opEquals(T : typeof(null))(T t) const {
		return kind == Kind.Null;
	}

	bool opEquals(B : bool)(B b) const {
		return kind == Kind.Boolean && boolean == b;
	}

	bool opEquals(I : long)(I i) const {
		return kind == Kind.Integer && integer == i;
	}

	bool opEquals(F : double)(F f) const {
		return kind == Kind.Floating && floating == f;
	}

	bool opEquals(S : string)(S s) const {
		return kind == Kind.String && str == s;
	}

	bool opEquals(A)(A a) const if (isArrayValue!A) {
		// Wrong type.
		if (kind != Kind.Array) {
			return false;
		}

		// Wrong length.
		if (array.length != a.length) {
			return false;
		}

		foreach (i, ref _; a) {
			if (array[i] != a[i]) {
				return false;
			}
		}

		return true;
	}

	bool opEquals(O)(O o) const if (isObjectValue!O) {
		// Wrong type.
		if (kind != Kind.Object) {
			return false;
		}

		// Wrong length.
		if (obj.length != o.length) {
			return false;
		}

		// Compare all the values.
		foreach (k, ref v; o) {
			auto vPtr = k in obj;
			if (vPtr is null || *vPtr != v) {
				return false;
			}
		}

		return true;
	}

	bool opEquals(M)(M m) const if (isMapValue!M) {
		// Wrong type.
		if (kind != Kind.Map) {
			return false;
		}

		// Wrong length.
		if (map.length != m.length) {
			return false;
		}

		// Compare all the values.
		foreach (ref k, ref v; m) {
			auto vPtr = Value(k) in map;
			if (vPtr is null || *vPtr != v) {
				return false;
			}
		}

		return true;
	}
}

auto visit(alias fun, Args...)(const ref Value v, auto ref Args args) {
	final switch (v.kind) with (Value.Kind) {
		case Null:
			return fun(null, args);

		case Boolean:
			return fun(v.boolean, args);

		case Integer:
			return fun(v.integer, args);

		case Floating:
			return fun(v.floating, args);

		case String:
			return fun(v.str, args);

		case Array:
			return fun(v.array, args);

		case Object:
			return fun(v.obj, args);

		case Map:
			return fun(v.map, args);
	}
}

// Assignement and comparison.
unittest {
	import std.meta;
	alias Cases = AliasSeq!(
		null,
		true,
		false,
		0,
		1,
		42,
		0.,
		3.141592,
		float.infinity,
		-float.infinity,
		"",
		"foobar",
		[1, 2, 3],
		[1, 2, 3, 4],
		["y" : true, "n" : false],
		["x" : 3, "y" : 5],
		["foo" : "bar"],
		["fizz" : "buzz"],
		["first" : [1, 2], "second" : [3, 4]],
		[["a", "b"] : [1, 2], ["c", "d"] : [3, 4]]
	);

	static testAllValues(E)(Value v, E expected, Value.Kind k) {
		assert(v.kind == k);

		bool found = false;
		foreach (I; Cases) {
			static if (!is(E == typeof(I))) {
				assert(v != I);
			} else if (expected == I) {
				found = true;
				assert(v == I);
			} else {
				assert(v != I);
			}
		}

		assert(found);
	}

	Value initVar;
	testAllValues(initVar, null, Value.Kind.Null);

	static testValue(E)(E expected, Value.Kind k) {
		Value v = expected;
		testAllValues(v, expected, k);
	}

	testValue(null, Value.Kind.Null);
	testValue(true, Value.Kind.Boolean);
	testValue(false, Value.Kind.Boolean);
	testValue(0, Value.Kind.Integer);
	testValue(1, Value.Kind.Integer);
	testValue(42, Value.Kind.Integer);
	testValue(0., Value.Kind.Floating);
	testValue(3.141592, Value.Kind.Floating);
	testValue(float.infinity, Value.Kind.Floating);
	testValue(-float.infinity, Value.Kind.Floating);
	testValue("", Value.Kind.String);
	testValue("foobar", Value.Kind.String);
	testValue([1, 2, 3], Value.Kind.Array);
	testValue([1, 2, 3, 4], Value.Kind.Array);
	testValue(["y" : true, "n" : false], Value.Kind.Object);
	testValue(["x" : 3, "y" : 5], Value.Kind.Object);
	testValue(["foo" : "bar"], Value.Kind.Object);
	testValue(["fizz" : "buzz"], Value.Kind.Object);
	testValue(["first" : [1, 2], "second" : [3, 4]], Value.Kind.Object);
	testValue([["a", "b"] : [1, 2], ["c", "d"] : [3, 4]], Value.Kind.Map);
}

// length
unittest {
	assert(Value("").length == 0);
	assert(Value("abc").length == 3);
	assert(Value([1, 2, 3]).length == 3);
	assert(Value([1, 2, 3, 4, 5]).length == 5);
	assert(Value(["foo", "bar"]).length == 2);
	assert(Value([3.2, 37.5]).length == 2);
	assert(Value([3.2 : "a", 37.5 : "b", 1.1 : "c"]).length == 3);
}

// toString
unittest {
	assert(Value().toString() == "null");
	assert(Value(true).toString() == "true");
	assert(Value(false).toString() == "false");
	assert(Value(0).toString() == "0");
	assert(Value(1).toString() == "1");
	assert(Value(42).toString() == "42");
	// FIXME: I have not found how to write down float in a compact form that is
	// not ambiguous with an integer in some cases. Here, D writes '1' by default.
	// std.format is not of great help on that one.
	// assert(Value(1.0).toString() == "1.0");
	assert(Value(4.2).toString() == "4.2");
	assert(Value(0.5).toString() == "0.5");

	assert(Value("").toString() == `""`);
	assert(Value("abc").toString() == `"abc"`);
	assert(Value("\n\t\n").toString() == `"\n\t\n"`);

	assert(Value([1, 2, 3]).toString() == "[1, 2, 3]");
	assert(
		Value(["y" : true, "n" : false]).toString() == `["y":true, "n":false]`);
	assert(Value([["a", "b"] : [1, 2], ["c", "d"] : [3, 4]]).toString()
		== `[["a", "b"]:[1, 2], ["c", "d"]:[3, 4]]`);
}
