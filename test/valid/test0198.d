//T has-passed:yes
//T compiles:yes
//T retval:0

int main() {
	const char* cmsg = "hello, world!";

	string world = cmsg[7 .. 13];
	assert(world.length == 6);
	assert(world[0] == 'w');
	assert(world[5] == '!');

	return 0;
}
