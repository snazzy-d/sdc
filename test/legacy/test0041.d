//T compiles:yes
//T has-passed:yes
//T dependency:test0041_import.d
//T retval:7
import test0041_import;

int main() {
	Foo foo;
	foo.bar();

	return 7;
}
