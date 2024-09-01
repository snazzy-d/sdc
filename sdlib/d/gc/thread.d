module d.gc.thread;

import d.gc.tcache;

void destroyThread() {
	threadCache.destroyThread();

	import d.gc.global;
	gState.remove(&threadCache);
}
