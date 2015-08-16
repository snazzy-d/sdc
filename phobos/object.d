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
	void* malloc(size_t);
	void* realloc(void*, size_t);
	void exit(int code);
	int printf(const char* fmt, ...);
	void* memset(void* ptr, int value, size_t num);
	void* memcpy(void* destination, void* source, size_t num);
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
}

