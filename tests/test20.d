// Basic import testing
//T compiles:yes
//T retval:42
//T dependency:test20_import.d
//T dependency:test20_import2.d

import test20_import;
import test20_import2;

int main()
{
    int a = importedFunction();
    int b = anotherImportedFunction();
    return a + b;
}

