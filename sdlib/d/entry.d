module d.entry;

extern(C):
int _Dmain();

int main() {
	import d.gc.thread;
	createProcess();

	try {
		return _Dmain();
	} catch (Throwable t) {
		return 1;
	}
}
