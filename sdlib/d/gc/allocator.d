module d.gc.allocator;

import d.gc.hpd;
import d.gc.spec;
import d.gc.util;

// Reserve memory in blocks of 1GB.
enum RefillSize = 1024 * 1024 * 1024;

struct HugePageAllocator {
private:
	import d.gc.base;
	shared(Base)* base;

	import d.sync.mutex;
	Mutex mutex;

	void* address;
	size_t size;
	ulong nextGeneration;

public:
	HugePageDescriptor* extract() shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(HugePageAllocator*) &this).extractImpl();
	}

private:
	HugePageDescriptor* extractImpl() {
		assert(mutex.isHeld(), "Mutex not held!");

		// We need to refill our address space pool.
		if (address is null) {
			address = base.reserveAddressSpace(RefillSize, HugePageSize);
			if (address is null) {
				return null;
			}

			size = RefillSize;
		}

		assert(address !is null && isAligned(address, HugePageSize),
		       "Invalid address!");
		assert(size >= HugePageSize && isAligned(size, HugePageSize),
		       "Invalid size!");

		auto hpd = base.allocHugePageDescriptor();
		if (hpd is null) {
			return null;
		}

		*hpd = HugePageDescriptor(address, nextGeneration++);
		address += HugePageSize;
		size -= HugePageSize;

		return hpd;
	}
}

unittest extract {
	import d.gc.base;
	shared Base base;
	scope(exit) base.clear();

	shared HugePageAllocator hpa;
	hpa.base = &base;

	ulong expectedGeneration = 0;
	auto hpd0 = hpa.extract();
	assert(hpd0.generation == expectedGeneration++);

	foreach (i; 1 .. RefillSize / HugePageSize) {
		assert(hpa.size == RefillSize - i * HugePageSize);

		// FIXME: Cannot be checked because of incomplete shared support.
		// assert(hpa.address is hpd0.address + i * HugePageSize);

		auto hpd = hpa.extract();
		assert(hpd.generation == expectedGeneration++);
		assert(hpd.address is hpd0.address + i * HugePageSize);
	}
}
