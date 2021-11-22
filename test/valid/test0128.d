//T compiles:no
//T has-passed:yes
// Test invalid specialisation.

template Qux(T : U*, U : V*, V) {
	enum Qux = T.sizeof + V.sizeof;
}

int main() {
	return Qux!(float**, int*);
}
