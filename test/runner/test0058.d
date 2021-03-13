// Name collision
//T has-passed:yes
//T compiles:no
//T dependency:test0058_import1.d
//T dependency:test0058_import2.d

import test0058_import1;
import test0058_import2;

int main() {
	int a = importedFunction();
	return a;
}
