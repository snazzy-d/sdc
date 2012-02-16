//T compiles:yes
//T dependency:test41_import.d
//T retval:7
import test41_import;

int main()
{
    Foo foo;
    foo.bar();
    return 7;
}

