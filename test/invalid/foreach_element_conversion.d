//T error: foreach_element_conversion.d:4:10:
//T error: Can't cast string to int.
void f(string[] a) {
	foreach (int e; a) {}
}
