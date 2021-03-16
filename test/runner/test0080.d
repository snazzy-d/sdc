//T compiles:yes
//T has-passed:yes
//T retval:8

alias bar = int;

int main() {
	return cast(int) ((int).sizeof + (bar).sizeof);
}
