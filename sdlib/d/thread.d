module d.thread;

extern(C) void __sd_thread_stop_the_world() {
	import d.gc.thread;
	stopTheWorld();
}

extern(C) void __sd_thread_restart_the_world() {
	import d.gc.thread;
	restartTheWorld();
}
