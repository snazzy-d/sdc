//T error: foreach_range_index_cast.d:4:18:
//T error: Can't cast int to bool.
void f() {
	foreach (bool i; 0 .. 1000) {}
}
