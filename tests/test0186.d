//T compiles:no
//T retval:0
//T has-passed:yes
// Tests nested default for no error on missing defaut in non-final switches
int main() {
	int x = 10;
	switch(x) {
		case 1 :
			switch (x) {
				case 1 :
					break;
			}
		case 2 :
			switch (x) {
				default :
					break;
			}
		default :
			break;
	}
}