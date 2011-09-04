//T compiles:yes

int main()
{
	string msg = "hello, world!";
	char* cmsg = msg.ptr;
	assert(*cmsg == 'h');
	
	char* cmsg2 = cmsg + 7;
	assert(*cmsg2 == 'w');
	
	cmsg2++;
	assert(*cmsg2 == 'o');
	
	cmsg2 += 2;
	assert(*cmsg2 == 'l');
	
	cmsg2 -= 3;
	assert(*cmsg2 == 'w');
	
	cmsg2--;
	assert(*cmsg2 == ' ');
	return 0;
}