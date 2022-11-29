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
}

struct HeapValue {
package:
	const(Descriptor)* tag;
	alias tag this;

	this(inout(Descriptor)* tag) inout {
		this.tag = tag;
	}

	ref inout(VString) toString() inout in(isString()) {
		return *(cast(inout(VString)*) &this);
	}

	ref inout(VArray) toArray() inout in(isArray()) {
		return *(cast(inout(VArray)*) &this);
	}

	ref inout(VObject) toObject() inout in(isObject()) {
		return *(cast(inout(VObject)*) &this);
	}

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
		impl = cast(Impl*) GC
			.malloc(Impl.sizeof + Value.sizeof * a.length,
			        GC.BlkAttr.NO_SCAN | GC.BlkAttr.APPENDABLE);

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
