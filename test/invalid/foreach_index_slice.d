//T error: foreach_index_slice.d:4:10:
//T error: index type int cannot cover the length of int[].
void f(int[] a) {
	foreach (int i, e; a) {}
}
