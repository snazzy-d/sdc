//T error: foreach_index_range.d:4:10:
//T error: index type ubyte cannot cover the length of int[256].
void f(int[256] a) {
	foreach (ubyte i, e; a) {}
}
