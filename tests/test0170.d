//T compiles:no
//T has-passed:yes

void main() {
	bool bl = bool.min - 1;
	bl = bool.max + 1;
	byte b = byte.min-1;
	b = byte.max+1;
	ushort us = ushort.max+1;
	us = ushort.min-1;
}
