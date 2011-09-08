//T compiles:yes

int main()
{
	string msg = "hello, world!";
	char* cmsg = msg.ptr;
	assert(*cmsg == 'h');
	
	char* cmsg2 = cmsg + 7;
	assert(*cmsg2 == 'w');
	assert(cmsg2 != cmsg);
	
	cmsg2++;
	assert(*cmsg2 == 'o');
	
	cmsg2 += 2;
	assert(*cmsg2 == 'l');
	
	cmsg2 -= 3;
	assert(*cmsg2 == 'w');
	
	cmsg2--;
	assert(*cmsg2 == ' ');
	
	assert(cmsg2 > cmsg);
	
	char* cmsg3 = cmsg - 3;
	assert(cmsg3 < cmsg);
	
	cmsg3 = cmsg;
	assert(cmsg3 == cmsg);
	return 0;
}
