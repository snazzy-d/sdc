import sys.mman;

// XXX: this is a bad port of mman header.
// We should be able to use actual prot of C header soon.
alias off_t = long; // Good for now.

enum Prot {
	None = 0x0,
	Read = 0x1,
	Write = 0x2,
	Exec = 0x4,
}

// TODO: confirm platform-specific values
enum MADV_DONTNEED = 4;
enum MADV_FREE = 8;

version(OSX) {
	enum Map {
		Shared = 0x01,
		Private = 0x02,
		Fixed = 0x10,
		Anon = 0x1000,
	}

	enum Advise {
		Purge = MADV_DONTNEED
	}
}

version(FreeBSD) {
	enum Map {
		Shared = 0x01,
		Private = 0x02,
		Fixed = 0x10,
		Anon = 0x1000,
	}

	enum Advise {
		Purge = MADV_DONTNEED
	}
}

version(linux) {
	enum Map {
		Shared = 0x01,
		Private = 0x02,
		Fixed = 0x10,
		Anon = 0x20,
	}

	enum Advise {
		Purge = MADV_FREE
	}
}

extern(C):
void* mmap(void* addr, size_t length, int prot, int flags, int fd,
           off_t offset);
int munmap(void* addr, size_t length);
int madvise(void* addr, size_t length, int advice);
