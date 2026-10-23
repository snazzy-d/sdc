//T error: foreach_index_nonintegral.d:4:10:
//T error: foreach: key cannot be of non-integral type float.
void f(int[3] a) {
	foreach (float i, e; a) {}
}
