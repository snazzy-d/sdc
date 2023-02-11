module d.gc.pages;

import sys.mman;

// TODO: Support alignment?
void* pages_map(void* addr, size_t size, size_t alignement) {
	auto ret = os_pages_map(addr, size, alignement);

	assert(ret is null || ret is addr);
	return ret;
}

void pages_unmap(void* addr, size_t size) {
	os_pages_unmap(addr, size);
}

private:

enum PagesFDTag = -1;
enum MMapFlags = Map.Private | Map.Anon;

// FIXME: Alignement.
void* os_pages_map(void* addr, size_t size, size_t alignement) {
	auto ret =
		mmap(addr, size, Prot.Read | Prot.Write, MMapFlags, PagesFDTag, 0);
	assert(ret !is null);

	auto MAP_FAILED = cast(void*) -1L;
	if (ret is MAP_FAILED) {
		return null;
	}

	if (addr !is null && ret !is addr) {
		// We mapped, but not where expected.
		os_pages_unmap(ret, size);
		return null;
	}

	// XXX: out contract
	assert(ret is null || (addr is null && ret !is addr)
		|| (addr !is null && ret is addr));
	return ret;
}

static void os_pages_unmap(void* addr, size_t size) {
	auto ret = munmap(addr, size);
	assert(ret != -1, "munmap failed!");
}
