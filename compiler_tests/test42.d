//T compiles:yes
//T dependency:test42_import.d
//T retval:8
import test42_import;

int main()
{
    auto foo = new Foo();
    return 8;
}

