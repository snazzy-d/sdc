module d.rt.dmain;

extern(C):

int main() {
	__sd_thread_init();

	try {
		return _Dmain();
	} catch (Throwable t) {
		return 1;
	}
}

int _Dmain();

void __sd_thread_init();
