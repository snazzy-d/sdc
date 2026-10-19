//T compiles:yes
//T has-passed:yes
//T retval:42

int main() {
	int a = 3;

	{
		int b = 5;

		b = a * b;
		a = b + a;
	}

	{
		int b;

		b = a + b;
		a = b + 24;
	}

	return a;
}
