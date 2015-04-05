//T compiles:yes
//T has-passed:yes
//T retval:0
// typeid.

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
}

