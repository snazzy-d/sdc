module d.gc.range;

struct AddressRange {
private:
	ulong min;
	ulong length;

public:
	this(void* min, void* max) {
		this.min = cast(size_t) min;
		this.length = max - min;
	}

	bool contains(void* ptr) const {
		auto v = cast(size_t) ptr;
		return (v - min) < length;
	}
}

unittest contains {
	import d.gc.spec;
	auto r = AddressRange(cast(void*) AddressSpace, null);

	assert(!r.contains(null));
	assert(!r.contains(cast(void*) 1));
	assert(!r.contains(cast(void*) AddressSpace - 1));

	r = AddressRange(cast(void*) 123, cast(void*) 456);
	assert(!r.contains(cast(void*) 122));
	assert(r.contains(cast(void*) 123));
	assert(r.contains(cast(void*) 234));
	assert(r.contains(cast(void*) 345));
	assert(r.contains(cast(void*) 455));
	assert(!r.contains(cast(void*) 456));
}
