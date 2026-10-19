//T compiles:yes
//T has-passed:yes
//T retval:23
// Construtor for builtin types.

alias T = int;

int main() {
	auto bo = bool(true);
	auto by = byte(1);
	auto ub = ubyte(1);
	auto sh = short(1);
	auto us = ushort(1);
	auto i = int(1);
	auto ui = uint(1);
	auto lo = long(1);
	auto ul = ulong(1);
	auto ce = cent(1);
	auto uc = ucent(1);

	return 20 + T(3);
}
