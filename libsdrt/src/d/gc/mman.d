module d.gc.mman;

void* map_chunks(size_t count) {
	import d.gc.spec;
	auto size = count * ChunkSize;
	auto ret = pages_map(null, size);
	
	auto offset = (cast(size_t) ret) & AlignMask;
	if (offset != 0) {
		pages_unmap(ret, size);
		ret = map_chunks_slow(count);
	}
	
	return ret;
}

void pages_unmap(void *addr, size_t size) {
	if (munmap(addr, size) == -1) {
		// TODO: display error.
		assert(0, "munmap failed");
	}
}

private:

void* pages_map(void* addr, size_t size) {
	auto ret = mmap(addr, size, Prot.Read | Prot.Write, Map.Private | Map.Anon, -1, 0);
	
	assert(ret !is null);
	
	auto MAP_FAILED = cast(void*) -1L;
	if (ret is MAP_FAILED) {
		ret = null;
	} else if (addr !is null && ret !is addr) {
		// We mapped, but not where expected.
		pages_unmap(ret, size);
		ret = null;
	}
	
	assert(ret is null || (addr is null && ret !is addr) || (addr !is null && ret is addr));
	return ret;
}

void* map_chunks_slow(size_t count) {
	import d.gc.spec;
	auto size = count * ChunkSize;
	auto alloc_size = size + ChunkSize - PageSize;
	
	// Integer overflow.
	if (alloc_size < ChunkSize) {
		return null;
	}
	
	auto ret = cast(void*) null;
	do {
		auto pages = pages_map(null, alloc_size);
		if (pages is null) {
			return null;
		}
		
		auto ipages = cast(size_t) pages;
		auto lead_size = ((ipages + ChunkSize - 1) & ~AlignMask) - ipages;
		
		ret = pages_trim(pages, alloc_size, lead_size, size);
	} while (ret is null);
	
	assert(ret !is null);
	return ret;
}

void* pages_trim(void* addr, size_t alloc_size, size_t lead_size, size_t size) {
	auto ret = cast(void*) ((cast(size_t) addr) + lead_size);
	
	assert(alloc_size >= lead_size + size);
	auto trail_size = alloc_size - lead_size - size;
	
	if (lead_size != 0) {
		pages_unmap(addr, lead_size);
	}
	
	if (trail_size != 0) {
		auto trail_addr = cast(void*) ((cast(size_t) ret) + size);
		pages_unmap(trail_addr, trail_size);
	}
	
	return ret;
}

private:

// XXX: this is a bad port of mman header.
// We should be able to use actual prot of C header soon.
alias off_t = long; // Good for now.

enum Prot {
	None	= 0x0,
	Read	= 0x1,
	Write	= 0x2,
	Exec	= 0x4,
}

enum Map {
	Shared	= 0x01,
	Private	= 0x02,
	Fixed	= 0x10,
	Anon	= 0x20,
}

extern(C):

void *mmap(void* addr, size_t length, int prot, int flags, int fd, off_t offset);
int munmap(void* addr, size_t length);

