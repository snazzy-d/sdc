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

enum Kind : ubyte {
	Null,
	Boolean,
	Integer,
	Float,
	String,
	Array,
	Object,
	Map,
}

struct Value {
private:
	Kind _kind;

	union {
		ulong _dummy;
		Value[string] _object;
		Value[Value] _map;
	}

	/**
	 * We use NaN boxing to pack all kind of values into a 64 bits payload.
	 * 
	 * NaN have a lot of bits we can play with in their payload. However,
	 * the range over which NaNs occuirs does not allow to store pointers
	 * 'as this'. this is a problem as the GC would then be unable to
	 * recognize them and might end up freeing live memory.
	 * 
	 * In order to work around that limitation, the whole range is
	 * shifted by FloatOffset so that the 0x0000 prefix overlap
	 * with pointers.
	 * 
	 * The value of the floating point number can be retrieved by
	 * subtracting FloatOffset from the payload's value.
	 * 
	 * The layout goes as follow:
	 * +--------+------------------------------------------------+
	 * | 0x0000 | true, false, null as well as pointers to heap. |
	 * +--------+------------------------------------------------+
	 * | 0x0001 |                                                |
	 * |  ....  | Positive floating point numbers.               |
	 * | 0x7ff0 |                                                |
	 * +--------+------------------------------------------------+
	 * | 0x7ff1 |                                                |
	 * |  ....  | Infinity, signaling NaN.                       |
	 * | 0x7ff8 |                                                |
	 * +--------+------------------------------------------------+
	 * | 0x7ff9 |                                                |
	 * |  ....  | Quiet NaN. Unused.                             |
	 * | 0x8000 |                                                |
	 * +--------+------------------------------------------------+
	 * | 0x8001 |                                                |
	 * |  ....  | Negative floating point numbers.               |
	 * | 0xfff0 |                                                |
	 * +--------+------------------------------------------------+
	 * | 0xfff1 |                                                |
	 * |  ....  | -Infinity, signaling -NaN.                     |
	 * | 0xfff8 |                                                |
	 * +--------+------------------------------------------------+
	 * | 0xfff9 |                                                |
	 * |  ....  | Quiet -NaN. Unused.                            |
	 * | 0xfffe |                                                |
	 * +--------+--------+ --------------------------------------+
	 * | 0xffff | 0x0000 | 32 bits integers.                     |
	 * +--------+--------+---------------------------------------+
	 */
	ulong payload;

	// We want the pointer values to be stored 'as this' so they can
	// be scanned by the GC. However, we also want to use the NaN
	// range in the double to store the pointers.
	// Because theses ranges overlap, we offset the values of the
	// double by a constant such as they do.
	enum FloatOffset = 0x0001000000000000;

	// If some of the bits in the mask are set, then this is a number.
	// If all the bits are set, then this is an integer.
	enum RangeMask = 0xffff000000000000;

	// For convenience, we provide prefixes
	enum HeapPrefix = 0x0000000000000000;
	enum IntegerPrefix = 0xffff000000000000;

	// A series of flags that allow for quick checks.
	enum OtherFlag = 0x02;
	enum BoolFlag = 0x04;

	// Values for constants.
	enum TrueValue = OtherFlag | BoolFlag | true;
	enum FalseValue = OtherFlag | BoolFlag | false;
	enum NullValue = OtherFlag;
	enum UndefinedValue = 0x00;

public:
	this(T)(T t) {
		this = t;
	}

	@property
	Kind kind() const {
		if (isNull()) {
			return Kind.Null;
		}

		if (isBoolean()) {
			return Kind.Boolean;
		}

		if (isInteger()) {
			return Kind.Integer;
		}

		if (isFloat()) {
			return Kind.Float;
		}

		if (isString()) {
			return Kind.String;
		}

		if (isArray()) {
			return Kind.Array;
		}

		return _kind;
	}

	bool isUndefined() const {
		return payload == UndefinedValue;
	}

	bool isNull() const {
		return payload == NullValue;
	}

	bool isBoolean() const {
		return (payload | 0x01) == TrueValue;
	}

	@property
	bool boolean() const nothrow in(isBoolean()) {
		return payload & 0x01;
	}

	bool isInteger() const {
		return (payload & RangeMask) == IntegerPrefix;
	}

	@property
	int integer() const nothrow in(isInteger()) {
		uint i = payload & uint.max;
		return i;
	}

	bool isNumber() const {
		return (payload & RangeMask) != 0;
	}

	bool isFloat() const {
		return isNumber() && !isInteger();
	}

	@property
	double floating() const in(isFloat()) {
		return Double(payload).toFloat();
	}

	bool isHeapObject() const {
		// FIXME: This shouldn't be necessary once everythig is NaN boxed.
		if (payload == 0) {
			return false;
		}

		return (payload & (RangeMask | OtherFlag)) == HeapPrefix;
	}

	@property
	Descriptor tag() const in(isHeapObject() && !isUndefined()) {
		return *(cast(Descriptor*) payload);
	}

	bool isString() const {
		return isHeapObject() && tag.isString();
	}

	@property
	string str() const in(isString()) {
		return String(payload).toString();
	}

	bool isArray() const {
		return isHeapObject() && tag.isArray();
	}

	@property
	inout(Value)[] array() inout in(isArray()) {
		auto a = inout(Array)(payload);
		return a.toArray();
	}

	bool isObject() const {
		return kind == Kind.Object;
	}

	@property
	inout(Value[string]) object() inout nothrow in(isObject()) {
		return _object;
	}

	bool isMap() const {
		return kind == Kind.Map;
	}

	@property
	inout(Value[Value]) map() inout nothrow in(isMap()) {
		return _map;
	}

	@property
	size_t length() const in(isString() || isArray() || isObject() || isMap()) {
		switch (kind) with (Kind) {
			case String:
				return str.length;
			case Array:
				return array.length;
			case Object:
				return object.length;
			case Map:
				return map.length;
			default:
				assert(0);
		}
	}

	/**
	 * Map and Object features
	 */
	inout(Value)* opBinaryRight(string op : "in")(string key) inout
			in(isObject() || isMap()) {
		return isMap() ? Value(key) in map : key in object;
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
	size_t toHash() const {
		return
			this.visit!(x => is(typeof(x) : typeof(null)) ? -1 : hashOf(x))();
	}

	/**
	 * Assignement
	 */
	Value opAssign()(typeof(null) nothing) {
		payload = NullValue;
		return this;
	}

	Value opAssign(B : bool)(B b) {
		payload = OtherFlag | BoolFlag | b;
		return this;
	}

	// FIXME: Promote to float for large ints.
	Value opAssign(I : long)(I i) in((i & uint.max) == i) {
		payload = i | IntegerPrefix;
		return this;
	}

	Value opAssign(F : double)(F f) {
		payload = Double(f).toPayload();
		return this;
	}

	Value opAssign(S : string)(S s) {
		payload = String(s).toPayload();
		return this;
	}

	Value opAssign(A)(A a) if (isArrayValue!A) {
		payload = Array(a).toPayload();
		return this;
	}

	Value opAssign(O)(O o) if (isObjectValue!O) {
		_kind = Kind.Object;
		_object = null;

		foreach (k, ref e; o) {
			_object[k] = Value(e);
		}

		payload = 0;
		return this;
	}

	Value opAssign(M)(M m) if (isMapValue!M) {
		_kind = Kind.Map;
		_map = null;

		foreach (ref k, ref e; m) {
			_map[Value(k)] = Value(e);
		}

		payload = 0;
		return this;
	}

	/**
	 * Equality
	 */
	bool opEquals(const ref Value rhs) const {
		return this.visit!((x, const ref Value rhs) => rhs == x)(rhs);
	}

	bool opEquals(T : typeof(null))(T t) const {
		return isNull();
	}

	bool opEquals(B : bool)(B b) const {
		return isBoolean() && boolean == b;
	}

	bool opEquals(I : long)(I i) const {
		return isInteger() && integer == i;
	}

	bool opEquals(F : double)(F f) const {
		return isFloat() && floating == f;
	}

	bool opEquals(S : string)(S s) const {
		return isString() && str == s;
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
		if (object.length != o.length) {
			return false;
		}

		// Compare all the values.
		foreach (k, ref v; o) {
			auto vPtr = k in object;
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
	final switch (v.kind) with (Kind) {
		case Null:
			return fun(null, args);

		case Boolean:
			return fun(v.boolean, args);

		case Integer:
			return fun(v.integer, args);

		case Float:
			return fun(v.floating, args);

		case String:
			return fun(v.str, args);

		case Array:
			return fun(v.array, args);

		case Object:
			return fun(v.object, args);

		case Map:
			return fun(v.map, args);
	}
}

struct Double {
	double value;

	this(double value) {
		this.value = value;
	}

	this(ulong payload) {
		auto x = payload - Value.FloatOffset;
		this(*(cast(double*) &x));
	}

	double toFloat() const {
		return value;
	}

	ulong toPayload() const {
		auto x = *(cast(ulong*) &value);
		return x + Value.FloatOffset;
	}
}

struct Descriptor {
private:
	ubyte refCount;
	Kind kind;

	uint length;

	static assert(Descriptor.sizeof == 8,
	              "Descriptors are expected to be 64 bits.");

public:
	bool isString() const {
		return kind == Kind.String;
	}

	bool isArray() const {
		return kind == Kind.Array;
	}
}

struct String {
private:
	struct StringImpl {
		Descriptor tag;
	}

	StringImpl* impl;
	alias impl this;

	this(ulong payload) {
		this(cast(StringImpl*) payload);
	}

	this(StringImpl* impl) {
		this.impl = impl;
	}

public:
	this(string s) in(s.length < uint.max) {
		import core.memory;
		impl = cast(StringImpl*) GC
			.malloc(StringImpl.sizeof + s.length,
			        GC.BlkAttr.NO_SCAN | GC.BlkAttr.APPENDABLE);

		tag.kind = Kind.String;
		tag.length = s.length & uint.max;

		import core.stdc.string;
		memcpy(impl + 1, s.ptr, s.length);
	}

	ulong toPayload() const {
		return cast(ulong) impl;
	}

	string toString() const {
		auto ptr = cast(immutable char*) (impl + 1);
		return ptr[0 .. tag.length];
	}
}

struct Array {
private:
	struct ArrayImpl {
		Descriptor tag;
	}

	ArrayImpl* impl;
	alias impl this;

	this(ulong payload) inout {
		this(cast(inout ArrayImpl*) payload);
	}

	this(inout ArrayImpl* impl) inout {
		this.impl = impl;
	}

public:
	this(A)(A a) if (isArrayValue!A) in(a.length < uint.max) {
		import core.memory;
		impl = cast(ArrayImpl*) GC
			.malloc(ArrayImpl.sizeof + Value.sizeof * a.length,
			        GC.BlkAttr.NO_SCAN | GC.BlkAttr.APPENDABLE);

		tag.kind = Kind.Array;
		tag.length = a.length & uint.max;

		foreach (i, ref e; toArray()) {
			e = Value(a[i]);
		}
	}

	ulong toPayload() const {
		return cast(ulong) impl;
	}

	inout(Value)[] toArray() inout {
		auto ptr = cast(inout Value*) (impl + 1);
		return ptr[0 .. tag.length];
	}
}

// Assignement and comparison.
unittest {
	import std.meta;
	alias Cases = AliasSeq!(
		// sdfmt off
		null,
		true,
		false,
		0,
		1,
		42,
		0.,
		3.141592,
		// float.nan,
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
		// sdfmt on
	);

	static testAllValues(E)(Value v, E expected, Kind k) {
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

		assert(found, v.toString());
	}

	Value initVar;
	assert(initVar.isUndefined());

	// testAllValues(initVar, null, Kind.Null);

	static testValue(E)(E expected, Kind k) {
		Value v = expected;
		testAllValues(v, expected, k);
	}

	testValue(null, Kind.Null);
	testValue(true, Kind.Boolean);
	testValue(false, Kind.Boolean);
	testValue(0, Kind.Integer);
	testValue(1, Kind.Integer);
	testValue(42, Kind.Integer);
	testValue(0., Kind.Float);
	testValue(3.141592, Kind.Float);
	// testValue(float.nan, Kind.Float);
	testValue(float.infinity, Kind.Float);
	testValue(-float.infinity, Kind.Float);
	testValue("", Kind.String);
	testValue("foobar", Kind.String);
	testValue([1, 2, 3], Kind.Array);
	testValue([1, 2, 3, 4], Kind.Array);
	testValue(["y" : true, "n" : false], Kind.Object);
	testValue(["x" : 3, "y" : 5], Kind.Object);
	testValue(["foo" : "bar"], Kind.Object);
	testValue(["fizz" : "buzz"], Kind.Object);
	testValue(["first" : [1, 2], "second" : [3, 4]], Kind.Object);
	testValue([["a", "b"] : [1, 2], ["c", "d"] : [3, 4]], Kind.Map);
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
