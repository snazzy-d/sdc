module object;

version (D_LP64) {
	alias size_t = ulong;
	alias ptrdiff_t = long;
} else {
	alias size_t = uint;
	alias ptrdiff_t = int;
}

alias string = immutable(char)[];

extern (C) {
	void exit(int code);
	int printf(const char* fmt, ...);
	void* memset(void* ptr, int value, size_t num);
	void* memcpy(void* destination, const void* source, size_t num);
}

class Object {
	this() {}
}

class TypeInfo {}
class ClassInfo : TypeInfo {
	ClassInfo base;
}

class Throwable {}
class Exception: Throwable {}
class Error: Throwable {}

// sdruntime
extern(C) {
	Object __sd_class_downcast(Object o, ClassInfo c);
	void __sd_eh_throw(Throwable t);
	int __sd_eh_personality(int, int, ulong, void*, void*);
	int __sd_array_outofbounds(string, int);
	
	// We should be using some dedicated array API instead of this.
	void* __sd_array_alloc(size_t size);
}

auto __sd_array_concat(T : U[], U)(T lhs, T rhs) {
	auto length = lhs.length + rhs.length;
	auto ptr = cast(U*) __sd_array_alloc(length * U.sizeof);
	memcpy(ptr, lhs.ptr, lhs.length * U.sizeof);
	memcpy(&ptr[lhs.length], rhs.ptr, rhs.length * U.sizeof);
	return ptr[0 .. length];
}
