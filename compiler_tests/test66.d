//T compiles:yes
//T retval:0

int main()
{
	string str = "foobar";
	string str2 = "raboof";
	foreach(i, c; str)
	{
		assert(c == str2[(str2.length - i) - 1]);
	}
	
	int count;
	foreach(char c; str)
	{
		if (c == 'o')
			count++;
	}
	assert(count == 2);
	
	char* mem = cast(char*)malloc(str.length);
	foreach(int i, c; str)
	{
		mem[i] = c;
	}
	
	foreach(size_t i; 0..str.length)
	{
		assert(mem[i] == str[i]);
	}
	
	foreach(i, ref char c; mem[0..3])
	{
		c = 'o';
	}
	
	foreach(i; 0..3)
	{
		assert(mem[i] == 'o');
	}
	
	char last;
	foreach(ref i, c; mem[0..1337])
	{
		last = c;
		if (i == 5)
			i = 1337;
	}
	assert(last == 'r');
	
	return 0;
}