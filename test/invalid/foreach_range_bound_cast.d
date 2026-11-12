//T error: foreach_range_bound_cast.d:4:22:
//T error: Can't cast immutable(char[]) to int.
void f() {
	foreach (int i; 0 .. "a") {}
}
