module d.entry;

extern(C):
int _Dmain();

int main() {
	import d.gc.capi;
	__sd_gc_init();

	import d.thread;
	__sd_thread_create();

	try {
		return _Dmain();
	} catch (Throwable t) {
		return 1;
	}
}
