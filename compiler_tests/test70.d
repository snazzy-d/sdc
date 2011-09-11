//T compiles:yes
//T retval:0
//? desc:Test the do-while loop.

int main()
{
	int i = 0;
	do {
		i++;
	} while(i > 10); // Should run once.
	assert(i == 1);
	
	do i--;
	while(i > -10);
	assert(i == -10);
	
	return 0;
}
