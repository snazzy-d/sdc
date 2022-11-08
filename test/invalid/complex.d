//T error: complex.d:6:20:
//T error: Invalid suffix: `i`.
// sdfmt off

void foo() {
	for (idouble i = -2i; i <= 2i; i += .125i) {}
}
