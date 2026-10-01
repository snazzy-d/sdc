//T error: deref_global.d:7:8:
//T error: Only pointers can be dereferenced.

static int g;

int main() {
	return *g;
}
