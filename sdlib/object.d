module object;

version(D_LP64) {
	alias size_t = ulong;
	alias ptrdiff_t = long;
} else {
	alias size_t = uint;
	alias ptrdiff_t = int;
}

alias string = immutable(char)[];

extern(C) {
	void* memset(void* ptr, int value, size_t num);
	void* memcpy(void* destination, const void* source, size_t num);
	void* memmove(void* destination, const void* source, size_t num);
}

class Object {
	this() {}
}

class TypeInfo {}

final class ClassInfo : TypeInfo {
	ClassInfo[] primaries;

	@property
	ClassInfo base() {
		const len = primaries.length;
		return len > 1 ? primaries[len - 2] : typeid(Object);
	}
}

class Throwable {}

class Exception : Throwable {}

class Error : Throwable {}

// sdruntime
extern(C) {
	void __sd_assert_fail(string, int);
	void __sd_assert_fail_msg(string, string, int);
	void __sd_eh_throw(Throwable t);
	int __sd_eh_personality(int, int, ulong, void*, void*);
	void __sd_array_outofbounds(string, int);
	void* __sd_gc_alloc(size_t);

	// We should be using some dedicated array API instead of this.
	void* __sd_gc_array_alloc(size_t size);
}

auto __sd_array_concat(T : U[], U)(T lhs, T rhs) {
	auto length = lhs.length + rhs.length;
	auto ptr = cast(U*) __sd_gc_array_alloc(length * U.sizeof);
	memcpy(ptr, lhs.ptr, lhs.length * U.sizeof);
	memcpy(&ptr[lhs.length], rhs.ptr, rhs.length * U.sizeof);
	return ptr[0 .. length];
}

private:

// FIXME: This would benefit from being a template, but we are
// currently unable to use template as runtime hooks.
// Instead, compiler magic is used to make this template like.
// If you call this directly, all bets are off.
Object __sd_class_downcast(Object o, ClassInfo c) {
	if (o is null) {
		return null;
	}

	auto oPrimaries = typeid(o).primaries;
	auto cDepth = c.primaries.length - 1;
	if (cDepth >= oPrimaries.length || oPrimaries[cDepth] !is c) {
		return null;
	}

	return o;
}

Object __sd_final_class_downcast(Object o, ClassInfo c) {
	if (o is null || typeid(o) !is c) {
		return null;
	}

	return o;
}
