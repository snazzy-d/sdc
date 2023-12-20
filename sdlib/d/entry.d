module d.entry;

extern(C):
int _Dmain();

int main() {
	import d.thread;
	__sd_thread_init();

	try {
		return _Dmain();
	} catch (Throwable t) {
		return 1;
	}
}
