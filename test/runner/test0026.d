//T compiles:yes
//T retval:2
//T has-passed:yes

int main() {
	int i;
	void* p = &i;

	return *(cast(int*) p) + 2;
}
