//T compiles:yes
//T has-passed:yes
//T retval:42
// Test correct generation of temporary.

int main() {
	int[15] ii;
	int i = 12;
	
	ii[++i] = i;
	ii[i++] += i++;
	
	return ii[i - 2] + i;
}

