//T compiles:yes

int main()
{
	string msg = "hello, world!";
	char* cmsg = msg.ptr;
	char* cmsg2 = cmsg + 7;
	
	assert(*cmsg == 'h');
	assert(*cmsg2 == 'w');
	return 0;
}