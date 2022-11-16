//T error: complex.d:6:20:
//T error: `i` is not a valid suffix.
// sdfmt off

void foo() {
	for (idouble i = -2i; i <= 2i; i += .125i) {}
}
