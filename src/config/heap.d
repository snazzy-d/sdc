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
	ref inout(VString) toVString() inout in(isString()) {
		return *(cast(inout(VString)*) &this);
	}

	ref inout(VArray) toVArray() inout in(isArray()) {
		return *(cast(inout(VArray)*) &this);
	}

	ref inout(VObject) toVObject() inout in(isObject()) {
		return *(cast(inout(VObject)*) &this);
	}

	ref inout(VMap) toVMap() inout in(isMap()) {
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

	hash_t toHash() const {
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

	bool opEquals(O)(O o) const if (isObjectValue!O) {
		if (isObject()) {
			return toVObject() == o;
		}

		if (isMap()) {
			return toVMap() == o;
		}

		return false;
	}

	bool opEquals(M)(M m) const if (isMapValue!M) {
		return isMap() && toVMap() == m;
	}

	/**
	 * Object/Map features.
	 */
	inout(Value)* opBinaryRight(string op : "in", K)(K key) inout
			if (isValue!K) {
		if (isObject()) {
			return key in toVObject();
		}

		if (isMap()) {
			return key in toVMap();
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
		import config.hash;
		return Hasher().hash(toString());
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
		import config.hash;
		return Hasher().hash(toArray());
	}

	string dump() const {
		import std.algorithm, std.format;
		return format!"[%-(%s, %)]"(toArray().map!(v => v.dump()));
	}

	inout(Value)[] toArray() inout {
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
}
