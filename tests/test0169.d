//T compiles:yes
//T has-passed:yes
//T retval:42

// Tests VRP, .min and .max 

int main() {
	assert (byte.min == -128);
	assert (short.min == -32768);
	auto lmn = long.min;
	auto ulmx = ulong.max;
	ubyte ub = 42;	
	byte b = -128;
	short sh = b;
	ushort ush = ub;
	int i = b+b+b+b+b+b+b-ush;
	
	ush = cast(int) ushort.max;
	byte b2 = ub+ushort.max-short.max+short.min-128;
	return b2+128;
	return 42;
}

