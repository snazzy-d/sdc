//T compiles:yes
//T has-passed:yes
//T retval:0
// GC slab finalizers

extern(C) void* __sd_gc_tl_flush_cache();
extern(C) void __sd_gc_collect();

extern(C) void* __sd_gc_alloc_finalizer(size_t size, void* finalizer);
extern(C) void __sd_gc_free(void* ptr);

static int destructorSum;
struct SlabDestructor(size_t size) {
	// The -1 is for the metadata storage.
	size_t[size / size_t.sizeof - 1] x;

	~this() {
		destructorSum += x[0];
	}
}

void destroyItem(T)(void* item, size_t size) {
	assert(size == T.sizeof, "Incorrect size passed to destructor.");
	(cast(T*) item).__dtor();
}

void allocateItem(size_t S)() {
	alias T = SlabDestructor!(S);
	auto ptr = __sd_gc_alloc_finalizer(T.sizeof, &destroyItem!T);
	auto iptr = cast(size_t) ptr;

	auto item = cast(T*) ptr;
	item.x[0] = S;

	enum BlockSize = 2 * 1024 * 1024;
	if ((iptr % BlockSize) == 0) {
		// The pointer is aligned on a block, this tend to lead to
		// false positive. To avoid this, we'll get a new one.
		allocateItem();
		__sd_gc_free(ptr);
	}
}

void allocateItems() {
	allocateItem!16();
	allocateItem!24();
	allocateItem!32();
	allocateItem!40();
	allocateItem!48();
	allocateItem!56();
	allocateItem!64();
	allocateItem!80();
	allocateItem!96();
	allocateItem!112();
	allocateItem!128();
	allocateItem!160();
	allocateItem!192();
	allocateItem!224();
	allocateItem!256();
	allocateItem!320();
	allocateItem!384();
	allocateItem!448();
	allocateItem!512();
	allocateItem!640();
	allocateItem!768();
	allocateItem!896();
	allocateItem!1024();
	allocateItem!1280();
	allocateItem!1536();
	allocateItem!1792();
	allocateItem!2048();
	allocateItem!2560();
	allocateItem!3072();
	allocateItem!3584();
	allocateItem!4096();
	allocateItem!5120();
	allocateItem!6144();
	allocateItem!7168();
	allocateItem!8192();
	allocateItem!10240();
	allocateItem!12288();
	allocateItem!14336();
}

void main() {
	// NOTE: the first slab block allocated is never collected, because it
	// appears on the stack during collection. Until this bug is fixed, consume
	// the first allocation.
	auto ptr = __sd_gc_alloc_finalizer(16, null);

	allocateItems();
	__sd_gc_tl_flush_cache();
	__sd_gc_collect();
	enum sumOfAllSizes = 16 + 24 + 32 + 40 + 48 + 56 + 64 + 80 + 96 + 112 + 128
		+ 160 + 192 + 224 + 256 + 320 + 384 + 448 + 512 + 640 + 768 + 896 + 1024
		+ 1280 + 1536 + 1792 + 2048 + 2560 + 3072 + 3584 + 4096 + 5120 + 6144
		+ 7168 + 8192 + 10240 + 12288 + 14336;
	assert(destructorSum == sumOfAllSizes, "Some destructors did not run!");
}
