//T compiles:yes
//T has-passed:yes
//T retval:13
// Tests Template-constraints

template isOdd(int N) if (N & 1) {
   enum isOdd = true;
}

template isOdd(int N) if (!(N & 1)) {
  enum isOdd = false;
}

struct Answer (alias answer) if (answer == 42) {
	const bool val = true;
	alias val this;
}

struct Answer (alias answer) if (answer != 42) {
	const bool val = false;
	alias val this;
}


auto handle(alias v)() if (v == 1) {
	return 6;	
}

auto handle(int v)() if (v != 3 && v != 1) {
	return 2;
}

auto handle(int v)() if (v == 3) {
	return 3;
}

auto itfi(alias v, T) (T t) if (v == 4) {
	return t;	
}


int main() {
	Answer!42 rightAnswer;
	Answer!12 wrongAnswer;
	
	assert(rightAnswer);
	assert(!wrongAnswer);

	assert(isOdd!11);
	assert(!isOdd!12);

	assert(itfi!4(true));

	return 
		handle!1() + // 6
		handle!2() + // 8
		handle!3() + // 11
		handle!4();  // 13	
}
