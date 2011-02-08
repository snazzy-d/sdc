//T compiles:yes
//T retval:0

enum Foo { One, Two, Three }
enum Foo1 { Four, }
    
enum Boolean : bool
{
    True = true,
    False = false
}

enum constant = "foo";

int main()
{
    Foo foo = Foo.One;
    if(foo != Foo.One || foo != 0) {
        return 1;
    }
    
    Boolean boolean = Boolean.True;
    if(!boolean) {
        return 1;
    }
    
    return 0;
}

