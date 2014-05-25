//T compiles:yes
//T has-passed:yes
//T retval:42
// Test correct generation of temporary.

int main() {
	int[16] ii;
	int i = 12;
	
	ii[++i] = i;
	ii[i++] += i;
	
	(*(&ii[i--] - 1)) += 2;
	
	return ii[i] + i;
}

