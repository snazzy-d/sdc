//T compiles:yes
//T retval:0

int main()
{
	string str = "foobar";
	string str2 = "raboof";
	
	int count = 0;
	for(int i = 0; i < 10; i++)
		count++;
	
	assert(count == 10);
	
	int i = str.length - 1;
	int j = 0;
	for(; i > -1; i--)
	{
		assert(str[i] == str2[j]);
		j++;
	}
	return 0;
}