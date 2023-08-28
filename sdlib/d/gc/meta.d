module d.gc.meta;

// Metadata returned in response to capacity queries
struct pInfo {
	void* address;
	size_t size;
	size_t usedCapacity;

	this(void* address, size_t size, size_t used) {
		assert(used <= size, "Used capacity exceeds alloc size!");

		this.address = address;
		this.size = size;
		this.usedCapacity = used;
	}
}
