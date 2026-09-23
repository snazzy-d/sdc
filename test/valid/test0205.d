//T compiles:yes
//T has-passed:yes
//T retval:0
// Address of a shared/immutable global is a link-time constant.
// The initializer is a relocation; the linker fills in the address.

immutable int gImm = 42;
immutable int* pImm = &gImm;

shared int gShared = 7;
shared int* pShared = &gShared;

struct Holder {
	immutable int* p = &gImm;
}

Holder h;

enum eImm = &gImm;

int main() {
	if (pImm !is &gImm) {
		return 1;
	}

	if (*pImm != 42) {
		return 2;
	}

	if (pShared !is &gShared) {
		return 3;
	}

	if (*pShared != 7) {
		return 4;
	}

	if (h.p !is &gImm) {
		return 5;
	}

	if (eImm !is &gImm) {
		return 6;
	}

	return 0;
}
