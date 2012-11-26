module d.processor.processor;

import d.processor.scheduler;

import d.ast.dmodule;

import std.algorithm;
import std.range;

class AbstractProcessor {
}

final class Processor(T) if(isPass!T) : AbstractProcessor {
	private Scheduler scheduler;
	
	T pass;
	
	this() {
		scheduler = new Scheduler(this);
		
		pass = new T(scheduler);
	}
	
	auto process(Module[] modules) {
		Process[] allTasks;
		foreach(m; modules) {
			auto t = new Process();
			t.init(m, d => pass.visit(cast(Module) d));
			
			allTasks ~= t;
		}
		
		auto tasks = allTasks;
		while(tasks) {
			tasks = tasks.filter!(t => t.result is null).array();
			
			foreach(t; tasks) {
				t.call();
			}
		}
		
		return cast(Module[]) allTasks.map!(t => t.result).array();
	}
}

