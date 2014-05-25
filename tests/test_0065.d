//T compiles:yes
//T has-passed:no
//T retval:0
//? desc:Test range foreach.

int main() {
	int i = 0;
	foreach(j; 1 .. 5) {
		i += j;
	}
	assert(i == 10);
	
	string str = "foobar";
	string str2 = "raboof";
	
	foreach(size_t j; 0 .. str.length) {
		assert(str[j] == str2[(str2.length - j) - 1]);
	}
	
	i = 0;
	foreach(char* it; str.ptr .. str.ptr + str.length) {
		assert(*it == str[i]);
		i++;
	}
	
	i = 0;
	foreach(ref j; 1 .. 10) {
		i += j;
		if(j == 5)
			j = 8;
	}
	assert(i == 24);
	
	// Break.
	i = 0;
	foreach(j; 0 .. 10) {
		if (j == 5)
			break;
		
		i++;
	}
	assert(i == 5);
	
	// Continue.
	i = 0;
	foreach(j; 0 .. 10) {
		if(j < 5)
			continue;
		
		i++;
	}
	assert(i == 5);
	return 0;
}

