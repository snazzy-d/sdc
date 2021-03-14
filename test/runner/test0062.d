//T has-passed:yes
//T compiles:yes
//T retval:0

int main() {
	string msg = "hello, world!";
	auto cmsg = msg.ptr;

	string hello = msg[0 .. 5];
	assert(hello.length == 5);
	assert(hello[0] == 'h');
	assert(hello[4] == 'o');

	string world = cmsg[7 .. 13];
	assert(world.length == 6);
	assert(world[0] == 'w');
	assert(world[5] == '!');

	return 0;
}
