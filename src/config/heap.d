module config.heap;

import config.map;
import config.traits;
import config.value;

enum Kind : ubyte {
	String,
	Array,
	Object,
	Map,
}

struct Descriptor {
package:
	Kind kind;
	ubyte refCount;

	uint length;

	static assert(Descriptor.sizeof == 8,
	              "Descriptors are expected to be 64 bits.");

public nothrow:
	bool isString() const {
		return kind == Kind.String;
	}

	bool isArray() const {
		return kind == Kind.Array;
	}

	bool isObject() const {
		return kind == Kind.Object;
	}

	bool isMap() const {
		return kind == Kind.Map;
	}
}

struct HeapValue {
package:
	const(Descriptor)* tag;
	alias tag this;

	this(const Descriptor* tag) {
		this.tag = tag;
	}

	this(H)(H h) if (isHeapValue!H) {
		this = h;
	}

package:
	ref inout(VString) toVString() inout nothrow in(isString()) {
		return *(cast(inout(VString)*) &this);
	}

	ref inout(VArray) toVArray() inout nothrow in(isArray()) {
		return *(cast(inout(VArray)*) &this);
	}

	ref inout(VObject) toVObject() inout nothrow in(isObject()) {
		return *(cast(inout(VObject)*) &this);
	}

	ref inout(VMap) toVMap() inout nothrow in(isMap()) {
		return *(cast(inout(VMap)*) &this);
	}

	/**
	 * Misc.
	 */
	string dump() const {
		if (isString()) {
			return toVString().dump();
		}

		if (isArray()) {
			return toVArray().dump();
		}

		if (isObject()) {
			return toVObject().dump();
		}

		if (isMap()) {
			return toVMap().dump();
		}

		assert(0, "Malformed HeapValue");
	}

	hash_t toHash() const nothrow {
		if (isString()) {
			return toVString().toHash();
		}

		if (isArray()) {
			return toVArray().toHash();
		}

		if (isObject()) {
			return toVObject().toHash();
		}

		if (isMap()) {
			return toVMap().toHash();
		}

		assert(0, "Malformed HeapValue");
	}

	/**
	 * Assignement.
	 */
	HeapValue opAssign(const VString s) {
		tag = &s.tag;
		return this;
	}

	HeapValue opAssign(const VArray a) {
		tag = &a.tag;
		return this;
	}

	HeapValue opAssign(const VObject o) {
		tag = &o.tag;
		return this;
	}

	HeapValue opAssign(const VMap m) {
		tag = &m.tag;
		return this;
	}

	HeapValue opAssign(S)(S s) if (isStringValue!S) {
		this = VString(s);
		return this;
	}

	HeapValue opAssign(A)(A a) if (isArrayValue!A) {
		this = VArray(a);
		return this;
	}

	HeapValue opAssign(O)(O o) if (isObjectValue!O) {
		this = VObject(o);
		return this;
	}

	HeapValue opAssign(M)(M m) if (isMapValue!M) {
		this = VMap(m);
		return this;
	}

	/**
	 * Equality check.
	 */
	bool opEquals(S)(S s) const if (isStringValue!S) {
		return isString() && toVString() == s;
	}

	bool opEquals(A)(A a) const if (isArrayValue!A) {
		return isArray() && toVArray() == a;
	}

	bool opEquals(M)(M m) const if (isMapLike!M) {
		if (isObject()) {
			return toVObject() == m;
		}

		if (isMap()) {
			return toVMap() == m;
		}

		return false;
	}

	bool opEquals(const HeapValue rhs) const {
		if (tag == rhs.tag) {
			return true;
		}

		if (length != rhs.length) {
			return false;
		}

		if (isString()) {
			return toVString() == rhs;
		}

		if (isArray()) {
			return toVArray() == rhs;
		}

		if (isObject()) {
			return toVObject() == rhs;
		}

		if (isMap()) {
			return toVMap() == rhs;
		}

		assert(0, "Malformed HeapValue");
	}

	bool opEquals(const ref Value rhs) const {
		return rhs == this;
	}

	bool opEquals(V)(V v) const if (isPrimitiveValue!V) {
		return false;
	}

	/**
	 * Indexing features.
	 */
	inout(Value) opIndex(K)(K key) inout if (isKeyLike!K) {
		if (isArray()) {
			return toVArray()[key];
		}

		if (isObject()) {
			return toVObject()[key];
		}

		if (isMap()) {
			return toVMap()[key];
		}

		return Value();
	}

	inout(Value)* opBinaryRight(string op : "in", K)(K key) inout
			if (isKeyLike!K) {
		if (isObject()) {
			return key in toVObject();
		}

		if (isMap()) {
			return key in toVMap();
		}

		return null;
	}
}

unittest {
	HeapValue h = VString("test");
	assert(h != Value());

	static testHeapEquality(T)(T t) {
		HeapValue hvs = VString("test");
		assert(hvs != t);
		assert(hvs != Value(t));

		// A few of numbers chosen at random.
		// https://dilbert.com/strip/2001-10-25
		HeapValue hva = VArray([9, 9, 9, 9]);
		assert(hva != t);
		assert(hva != Value(t));

		HeapValue hvo = VObject(["ping": "pong"]);
		assert(hvo != t);
		assert(hvo != Value(t));

		HeapValue hvm = VMap(["ping": "pong"]);
		assert(hvm != t);
		assert(hvm != Value(t));
	}

	testHeapEquality("");
	testHeapEquality(1);
	testHeapEquality(2.3);
	testHeapEquality([1, 2, 3]);
	testHeapEquality(["foo": "bar"]);
	testHeapEquality([1: "fizz", 2: "buzz"]);
}

struct VString {
private:
	struct Impl {
		Descriptor tag;
	}

	Impl* impl;
	alias impl this;

public:
	this(string s) in(s.length < uint.max) {
		import core.memory;
		impl = cast(Impl*) GC
			.malloc(Impl.sizeof + s.length,
			        GC.BlkAttr.NO_SCAN | GC.BlkAttr.APPENDABLE);

		tag.kind = Kind.String;
		tag.length = s.length & uint.max;

		import core.stdc.string;
		memcpy(impl + 1, s.ptr, s.length);
	}

	bool opEquals(string s) const {
		return toString() == s;
	}

	bool opEquals(const VString rhs) const {
		return this == rhs.toString();
	}

	bool opEquals(const HeapValue rhs) const {
		return rhs == this;
	}

	bool opEquals(const Value v) const {
		return v == this;
	}

	bool opEquals(V)(V v) const if (isValue!V) {
		return false;
	}

	hash_t toHash() const nothrow {
		import config.hash;
		return Hasher().hash(toString());
	}

	string toString() const nothrow {
		auto ptr = cast(immutable char*) (impl + 1);
		return ptr[0 .. tag.length];
	}

	string dump() const {
		import std.format;
		auto s = toString();
		return format!"%(%s%)"((&s)[0 .. 1]);
	}
}

unittest {
	static testString(string s) {
		auto sv = VString(s);
		assert(sv == s);

		auto sv2 = VString(s);
		assert(sv == sv2);

		import config.hash;
		assert(hash(sv) == hash(s));
	}

	testString("");
	testString("a");
	testString("toto");
	testString("\0\0\0\0\0\0\0");
	testString("🙈🙉🙊");

	assert(VString("test") != Value());
	assert(VString("test") == Value("test"));

	static testStringEquality(T)(T t) {
		auto s = VString("test");
		assert(s != t);
		assert(s != Value(t));
	}

	testStringEquality("");
	testStringEquality(1);
	testStringEquality(2.3);
	testStringEquality([1, 2, 3]);
	testStringEquality(["foo": "bar"]);
	testStringEquality([1: "fizz", 2: "buzz"]);
}

struct VArray {
private:
	struct Impl {
		Descriptor tag;
	}

	Impl* impl;
	alias impl this;

public:
	this(A)(A a) if (isArrayValue!A) in(a.length < uint.max) {
		import core.memory;
		impl = cast(Impl*) GC.malloc(Impl.sizeof + Value.sizeof * a.length,
		                             GC.BlkAttr.APPENDABLE);

		tag.kind = Kind.Array;
		tag.length = a.length & uint.max;

		foreach (i, ref e; toArray()) {
			e = Value(a[i]);
		}
	}

	inout(Value) opIndex(size_t index) inout {
		return (index < tag.length) ? toArray()[index] : Value();
	}

	inout(Value) opIndex(const Value v) inout {
		return v.isInteger() ? this[v.integer] : Value();
	}

	inout(Value) opIndex(V)(V v) inout if (isValue!V) {
		return Value();
	}

	bool opEquals(A)(A a) const if (isArrayValue!A) {
		// Wrong length.
		if (tag.length != a.length) {
			return false;
		}

		foreach (i, ref _; a) {
			if (this[i] != a[i]) {
				return false;
			}
		}

		return true;
	}

	bool opEquals(const VArray rhs) const {
		return toArray() == rhs.toArray();
	}

	bool opEquals(const HeapValue rhs) const {
		return rhs == this;
	}

	bool opEquals(const Value v) const {
		return v == this;
	}

	bool opEquals(V)(V v) const if (isValue!V && !isArrayValue!V) {
		return false;
	}

	hash_t toHash() const nothrow {
		import config.hash;
		return Hasher().hash(toArray());
	}

	string dump() const {
		import std.algorithm, std.format;
		return format!"[%-(%s, %)]"(toArray().map!(v => v.dump()));
	}

	inout(Value)[] toArray() inout nothrow {
		auto ptr = cast(inout Value*) (impl + 1);
		return ptr[0 .. tag.length];
	}
}

unittest {
	static testArray(T)(T[] a) {
		auto va = VArray(a);
		assert(va == a);

		import std.algorithm, std.array;
		auto a2 = a.map!(e => Value(e)).array();
		auto va2 = VArray(a2);
		assert(va2 == a);
		assert(va2 == va);
		assert(va2 == a2);

		import config.hash;
		assert(hash(va) == hash(a));
		assert(hash(va2) == hash(a));
		assert(hash(va2) == hash(va));
		assert(hash(va2) == hash(a2));
	}

	int[] empty;
	testArray(empty);
	testArray(["", "foo", "bar"]);
	testArray([1, 2, 3, 4, 5]);

	assert(VArray([9, 9, 9, 9]) != Value());
	assert(VArray([9, 9, 9, 9]) == Value([9, 9, 9, 9]));

	static testArrayEquality(T)(T t) {
		auto a = VArray([9, 9, 9, 9]);
		assert(a != t);
		assert(a != Value(t));
	}

	testArrayEquality("");
	testArrayEquality(1);
	testArrayEquality(2.3);
	testArrayEquality([1, 2, 3]);
	testArrayEquality(["foo": "bar"]);
	testArrayEquality([1: "fizz", 2: "buzz"]);

	auto a = VArray([0, 11, 22, 33, 44, 55]);
	assert(a[-1].isUndefined());
	assert(a[6].isUndefined());
	assert(a[""].isUndefined());
	assert(a["foo"].isUndefined());

	foreach (i; 0 .. 6) {
		assert(a[i] == 11 * i);
		assert(a[Value(i)] == 11 * i);
	}
}
