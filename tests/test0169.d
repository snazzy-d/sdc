//T compiles:yes
//T has-passed:yes
//T retval:42

// Tests VRP, .min and .max 
struct S {
	bool bl;
	ubyte sub;
}


int main() {
	assert (byte.min == -128);
	assert (short.min == -32768);
	assert (ulong.max == -1LU);
	bool bl = 1; //true
	assert(bl);
	bl = 0;// false
	assert(!bl);
	bl = 1-1;
	assert(!bl);
	bl = true-1; //false
	assert(!bl);
	bl = (-1UL)-(-1UL-1); // true
	assert(bl);


	byte b = -128;
	
	long l = -1UL;
	short s1 = -1UL-255+265+(-1UL); 
	ubyte ub = 42;
	ubyte ub2 = 255; 	
	byte b2 = -42;
	short sh = b;
	ushort ush = ub;
	ubyte bc = 'A';
	int i = b+b+b+b+b+b+b-ush;
	S s;
	s.sub = 128;
	ushort ush2 = cast(int) cast(byte) ulong.max;
	assert(ush2 == ushort.max);
	byte b3 = ub+ushort.max-short.max+short.min-128;
	return b3 + s.sub;
 
}
