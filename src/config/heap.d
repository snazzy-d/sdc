module config.heap;

import config.map;
import config.traits;
import config.value;

struct Descriptor {
package:
	Kind kind;
	ubyte refCount;

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

package:
	ref inout(VString) toString() inout in(isString()) {
		return *(cast(inout(VString)*) &this);
	}

	ref inout(VArray) toArray() inout in(isArray()) {
		return *(cast(inout(VArray)*) &this);
	}

	ref inout(VObject) toObject() inout in(isObject()) {
		return *(cast(inout(VObject)*) &this);
	}

	ref inout(VMap) toMap() inout in(isMap()) {
		return *(cast(inout(VMap)*) &this);
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
		return isString() && toString() == s;
	}

	bool opEquals(A)(A a) const if (isArrayValue!A) {
		return isArray() && toArray() == a;
	}

	bool opEquals(O)(O o) const if (isObjectValue!O) {
		if (isObject()) {
			return toObject() == o;
		}

		if (isMap()) {
			return toMap() == o;
		}

		return false;
	}

	bool opEquals(M)(M m) const if (isMapValue!M) {
		return isMap() && toMap() == m;
	}

	/**
	 * Object/Map features.
	 */
	inout(Value)* opBinaryRight(string op : "in", K)(K key) inout
			if (isValue!K) {
		if (isObject()) {
			return key in toObject();
		}

		if (isMap()) {
			return key in toMap();
		}

		return null;
	}
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

	bool opEquals(const ref VString rhs) const {
		return this == rhs.toString();
	}

	hash_t toHash() const {
		return hashOf(toString());
	}

	string toString() const {
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
	static testString(string v) {
		auto s = VString(v);

		assert(s == v);
		assert(hashOf(s) == hashOf(v));

		auto s2 = VString(v);
		assert(s == s2);
	}

	foreach (s; ["", "a", "toto", "\0\0\0\0\0\0\0", "🙈🙉🙊"]) {
		testString(s);
	}
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
		if (index >= tag.length) {
			return inout(Value)();
		}

		return toArray()[index];
	}

	bool opEquals(const ref VArray rhs) const {
		return toArray() == rhs.toArray();
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

	hash_t toHash() const {
		return hashOf(toArray());
	}

	string toString() const {
		import std.format;
		auto a = toArray();
		return format!"%(%s%)"((&a)[0 .. 1]);
	}

	inout(Value)[] toArray() inout {
		auto ptr = cast(inout Value*) (impl + 1);
		return ptr[0 .. tag.length];
	}
}

unittest {
	static testArray(T)(T[] v) {
		auto a = VArray(v);
		assert(a == v);

		import std.algorithm, std.array;
		auto v2 = v.map!(e => Value(e)).array();
		auto a2 = VArray(v2);

		assert(a == a2);
		assert(hashOf(a) == hashOf(a2));
		assert(a2 == v2);
		assert(hashOf(a2) == hashOf(v2));
	}

	int[] empty;
	testArray(empty);
	testArray(["", "foo", "bar"]);
	testArray([1, 2, 3, 4, 5]);
}
