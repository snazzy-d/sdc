// Basic import testing
//T compiles:yes
//T retval:42
//T has-passed:yes
//T dependency:test0020_import.d
//T dependency:test0020_import2.d

import test0020_import;
import test0020_import2;

int main() {
	int a = importedFunction();
	int b = anotherImportedFunction();

	return a + b;
}
