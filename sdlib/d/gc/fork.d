module d.gc.fork;

import core.stdc.pthread;

void setupFork() {
	if (pthread_atfork(prepare, parent, child) != 0) {
		import core.stdc.stdlib, core.stdc.stdio;
		printf("pthread_atfork failed!");
		exit(1);
	}
}

void prepare() {
	/**
	 * Before forking, we want to take all the locks.
	 * This ensures that no other thread holds on GC
	 * resources while forking, and would find itself
	 * unable to release them in the child.
	 * The order in which locks are taken is important
	 * as taking them in the wrong order will cause
	 * deadlocks.
	 * 
	 * FIXME: At the moment, we only take the lock for
	 *        the collection process. This ensures we
	 *        can use the fork/exec pattern safely, but
	 *        it will nto leave the GC in a usable state
	 *        in the child.
	 */
	import d.gc.collector;
	collectorPrepareForFork();
}

void parent() {
	import d.gc.collector;
	collectorPostForkParent();
}

void child() {
	import d.gc.collector;
	collectorPostForkChild();
}
