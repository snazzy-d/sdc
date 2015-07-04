//T compiles:yes
//T has-passed:yes
//T retval:0
// memory allocator test.

class A {}
class B : A { ulong a; }
class C : B { ulong b; }
class D : C { ulong c; ulong d; }

class L { ulong[4000] l; }

enum S = 4096 * 16;

A[S] as;
A[S] bs;
A[S] cs;
A[S] ds;
L[S / 128] ls;

extern(C) void _tl_gc_free(void* ptr);
extern(C) void* _tl_gc_alloc(size_t size);
extern(C) void* _tl_gc_realloc(void* ptr, size_t size);

void main() {
	foreach(i; 0 .. S) {
		as[i] = new A();
		bs[i] = new B();
		cs[i] = new C();
		ds[i] = new D();
		
		if (i % 128 == 0) {
			ls[i / 128] = new L();
		}
	}
	
	foreach(i; 0 .. S / 4) {
		_tl_gc_free(cast(void*) as[i]);
		_tl_gc_free(cast(void*) bs[i]);
		_tl_gc_free(cast(void*) cs[i]);
		_tl_gc_free(cast(void*) ds[i]);
		as[i] = new D();
		bs[i] = new D();
		cs[i] = new D();
		ds[i] = new D();
	}
	
	foreach(i; 0 .. S) {
		_tl_gc_free(cast(void*) as[i]);
		_tl_gc_free(cast(void*) bs[i]);
		_tl_gc_free(cast(void*) cs[i]);
		_tl_gc_free(cast(void*) ds[i]);
		as[i] = new A();
		bs[i] = new A();
		cs[i] = new A();
		ds[i] = new A();
		
		if (i % 128 == 0) {
			_tl_gc_free(cast(void*) ls[i / 128]);
		}
	}
	
	auto b0 = _tl_gc_alloc(25 * 1024 * 1024);
	auto b1 = _tl_gc_alloc(13 * 1024 * 1024);
	auto b2 = _tl_gc_alloc(52 * 1024 * 1024);
	auto b3 = _tl_gc_alloc(27 * 1024 * 1024);
	_tl_gc_free(b0);
	_tl_gc_free(b1);
	_tl_gc_free(b2);
	_tl_gc_free(b3);
	
	_tl_gc_free(null);
	
	// Realloc degenerate cases (null ptr, 0 size).
	auto r = _tl_gc_realloc(null, 0);
	assert(r is null);
	
	r = _tl_gc_realloc(r, 20);
	assert(r !is null);
	
	r = _tl_gc_realloc(r, 0);
	assert(r is null);
	
	// Small realloc
	auto r0 = _tl_gc_realloc(r, 50);
	auto r1 = _tl_gc_realloc(r0, 150);
	assert(r1 !is r0);
	
	r1 = _tl_gc_realloc(r1, 50);
	assert(r1 is r0);
	
	r1 = _tl_gc_realloc(r1, 55);
	assert(r1 is r0);
	
	// Large realloc
	r0 = _tl_gc_realloc(r1, 34 * 4096);
	r1 = _tl_gc_realloc(r0, 55 * 4096);
	assert(r0 !is r1);
	
	r1 = _tl_gc_realloc(r1, 34 * 4096);
	assert(r1 is r0);
	
	r1 = _tl_gc_realloc(r1, 35 * 4096);
	assert(r1 is r0);
	
	// Huge realloc
	r0 = _tl_gc_realloc(r1, 34 * 1024 * 1024);
	r1 = _tl_gc_realloc(r0, 55 * 1024 * 1024);
	assert(r0 !is r1);
	
	r0 = _tl_gc_realloc(r1, 34 * 1024 * 1024);
	assert(r0 !is r1);
	
	r1 = _tl_gc_realloc(r0, 35 * 1024 * 1024);
	assert(r1 is r0);
}

