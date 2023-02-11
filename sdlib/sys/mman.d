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

version(OSX) {
	enum Map {
		Shared = 0x01,
		Private = 0x02,
		Fixed = 0x10,
		Anon = 0x1000,
	}
}

version(FreeBSD) {
	enum Map {
		Shared = 0x01,
		Private = 0x02,
		Fixed = 0x10,
		Anon = 0x1000,
	}
}

version(linux) {
	enum Map {
		Shared = 0x01,
		Private = 0x02,
		Fixed = 0x10,
		Anon = 0x20,
	}
}

extern(C):
void* mmap(void* addr, size_t length, int prot, int flags, int fd,
           off_t offset);
int munmap(void* addr, size_t length);
