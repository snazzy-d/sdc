//T compiles:yes
float x(int y) {
	return y;
}

int main() {
	{
		float x = 3.14f;
		double x2 = 3.14;
	}

	{
		float chimp = -23.0;
	}

	double p = 420.0;
	float lightSpeed = 299792458.0;
	char ch = 'a';
	double x = ch;
	char g = cast(char) x;
	return 0;
}
