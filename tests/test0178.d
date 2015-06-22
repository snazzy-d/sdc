//T compiles:no
//T has-passed:no
// Invalid closure frame access


int main() {
    int c; // local to main(closure)
	
	static struct S { // static structs are not in the closure.
        int f() {return c;} //invalid access of local
    }
	
    return S.init.f();
}
