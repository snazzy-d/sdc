//T compiles:yes
//T retval:0
//T has-passed:yes
// Tests derived class defined in superclass

class Alpha {
	class Bravo : Alpha {}
}


int main() {
        return 0;
}
