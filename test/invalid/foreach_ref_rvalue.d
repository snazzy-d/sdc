//T error: foreach_ref_rvalue.d:9:10:
//T error: Ref element isn't an lvalue.
int[3] make() {
	int[3] a = [1, 2, 3];
	return a;
}

int main() {
	foreach (ref e; make()) {
		e += 10;
	}

	return 0;
}
