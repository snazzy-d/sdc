module d.thread;

extern(C) void __sd_thread_stop_the_world() {
	import d.gc.global;
	gState.stopTheWorld();
}

extern(C) void __sd_thread_restart_the_world() {
	import d.gc.global;
	gState.restartTheWorld();
}
