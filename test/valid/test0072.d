//T compiles:yes
//T has-passed:yes
//T retval:4

template Foo(T) {
	T bar;
}

int main() {
	Foo!int.bar = 4;
	return Foo!int.bar;
}
