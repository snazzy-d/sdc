//T compiles:yes
//T has-passed:yes
//T retval:42

enum A : byte {
	Foo,
}

enum B : long {
	Bar,
}

int main() {
	if (A.Foo.sizeof < B.Bar.sizeof) {
		return 42;
	} else {
		return 0;
	}
}
