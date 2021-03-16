//T compiles:yes
//T has-passed:yes
//T retval:0

int main() {
	int a;
	auto b = &a;
	auto c = b;
	bool d = b == c;
	return 0;
}
