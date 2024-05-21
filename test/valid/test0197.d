//T compiles:yes
//T has-passed:yes
//T retval:0
// GC stress test.

extern(C) void __sd_gc_collect();
extern(C) void* __sd_gc_alloc(size_t size);

struct Link {
	Link* next;

	this(Link* next) {
		this.next = next;
	}
}

void main() {
	enum NodeCount = 10000000;

	foreach (loop; 0 .. 20) {
		auto ll = new Link(null);
		foreach (i; 0 .. NodeCount) {
			ll = new Link(ll);
		}

		__sd_gc_collect();
	}
}
