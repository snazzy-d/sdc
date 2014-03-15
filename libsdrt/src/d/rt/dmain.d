module d.rt.dmain;

extern(C):

int _Dmain();

int main() {
	try {
		return _Dmain();
	} catch(Throwable t) {
		return 1;
	}
}

