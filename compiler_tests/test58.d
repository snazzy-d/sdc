// Name collision
//T compiles:no
//T dependency:test58_import1.d
//T dependency:test58_import2.d

import test58_import1;
import test58_import2;

int main()
{
    int a = importedFunction();
    return a;
}
