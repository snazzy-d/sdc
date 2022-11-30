module config.value;

import config.heap;
import config.map;
import config.traits;

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
	union {
		ulong payload;
		HeapValue heapValue;
	}

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

		if (isObject()) {
			return Kind.Object;
		}

		if (isMap()) {
			return Kind.Map;
		}

		assert(0, "Invalid value kind.");
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

	bool isHeapValue() const {
		// FIXME: This shouldn't be necessary once everything is NaN boxed.
		if (heapValue is null) {
			return false;
		}

		return (payload & (RangeMask | OtherFlag)) == HeapPrefix;
	}

	bool isString() const {
		return isHeapValue() && heapValue.isString();
	}

	@property
	ref str() const in(isString()) {
		return heapValue.toString();
	}

	bool isArray() const {
		return isHeapValue() && heapValue.isArray();
	}

	@property
	ref array() inout in(isArray()) {
		return heapValue.toArray();
	}

	bool isObject() const {
		return isHeapValue() && heapValue.isObject();
	}

	@property
	ref object() inout in(isObject()) {
		return heapValue.toObject();
	}

	bool isMap() const {
		return isHeapValue() && heapValue.isMap();
	}

	@property
	ref map() inout in(isMap()) {
		return heapValue.toMap();
	}

	@property
	size_t length() const in(isHeapValue()) {
		return heapValue.length;
	}

	/**
	 * Map and Object features
	 */
	inout(Value)* opBinaryRight(string op : "in")(string key) inout
			in(isObject() || isMap()) {
		return isMap() ? key in heapValue.toMap() : key in object;
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
			} else static if (is(T : const VString)) {
				return v.dump();
			} else {
				import std.conv;
				return to!string(v);
			}
		})();
	}

	string dump() const {
		// FIXME: This toString/dump thing needs to be sorted out.
		return this.toString();
	}

	@trusted
	hash_t toHash() const {
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
		heapValue = VString(s);
		return this;
	}

	Value opAssign(A)(A a) if (isArrayValue!A) {
		heapValue = VArray(a);
		return this;
	}

	Value opAssign(O)(O o) if (isObjectValue!O) {
		heapValue = VObject(o);
		return this;
	}

	Value opAssign(M)(M m) if (isMapValue!M) {
		heapValue = VMap(m);
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

	bool opEquals(const ref VString rhs) const {
		return isString() && str == rhs;
	}

	bool opEquals(S : string)(S s) const {
		return isString() && str == s;
	}

	bool opEquals(const ref VArray rhs) const {
		return isArray() && array == rhs;
	}

	bool opEquals(A)(A a) const if (isArrayValue!A) {
		return isArray() && array == a;
	}

	bool opEquals(const ref VObject rhs) const {
		return isObject() && object == rhs;
	}

	bool opEquals(O)(O o) const if (isObjectValue!O) {
		return isObject() && object == o;
	}

	bool opEquals(M)(M m) const if (isMapValue!M) {
		return isMap() && map == m;
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
			} else if (I == expected) {
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
	testValue(["y": true, "n": false], Kind.Object);
	testValue(["x": 3, "y": 5], Kind.Object);
	testValue(["foo": "bar"], Kind.Object);
	testValue(["fizz": "buzz"], Kind.Object);
	testValue(["first": [1, 2], "second": [3, 4]], Kind.Object);
	testValue([["a", "b"]: [1, 2], ["c", "d"]: [3, 4]], Kind.Map);
}

// length
unittest {
	assert(Value("").length == 0);
	assert(Value("abc").length == 3);
	assert(Value([1, 2, 3]).length == 3);
	assert(Value([1, 2, 3, 4, 5]).length == 5);
	assert(Value(["foo", "bar"]).length == 2);
	assert(Value([3.2, 37.5]).length == 2);
	assert(Value([3.2: "a", 37.5: "b", 1.1: "c"]).length == 3);
}

// toString
unittest {
	assert(Value(null).toString() == "null");
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
		Value(["y": true, "n": false]).toString() == `["y": true, "n": false]`);
	assert(Value([["a", "b"]: [1, 2], ["c", "d"]: [3, 4]]).toString()
		== `[["a", "b"]: [1, 2], ["c", "d"]: [3, 4]]`);
}
