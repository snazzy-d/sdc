module d.processor.scheduler;

import d.ast.base;
import d.ast.declaration;

import std.algorithm;
import std.range;
import std.traits;

import core.thread;

alias Symbol delegate(Declaration) ProcessDg;

final class Process : Fiber {
	Declaration source;
	Symbol result;
	
	this() {
		super({
			assert(0, "You must initialize process before using it.");
		});
	}
	
	void init(Declaration decl, ProcessDg dg) {
		source = decl;
		result = null;
		
		reset(delegate void() {
			result = dg(source);
		});
	}
}

template Scheduler(P) {
private:
	alias P.Steps Steps;
	enum LastStep = EnumMembers!Steps[$ - 1];
	
	bool checkEnumElements() {
		uint i;
		foreach(s; EnumMembers!Steps) {
			if(s != i++) return false;
		}
	
		return true;
	}
	
	enum isPassEnum = is(Steps : uint) && checkEnumElements();
	enum isPass = is(typeof(P.init.state.declaration) : Declaration) && isPassEnum;
	
	static assert(isPass, "you can only schedule passes.");
	
	template isDeclarationRange(R) {
		enum isDeclarationRange = isInputRange!R && is(ElementType!R : Declaration);
	}
	
	struct Result {
		Steps step;
		Symbol result;
	}
	
public:
	final class Scheduler {
		P pass;
		
		Symbol[Declaration] processed;
		
		this(P pass) {
			this.pass = pass;
		}
		
		private Process getProcess() {
			/*
			if(pool) {
				auto ret = pool[$ - 1];
				
				pool = pool[0 .. $ - 1];
				pool.assumeSafeAppend();
				
				return ret;
			}
			*/
			return new Process();
		}
		
		auto require(Declaration d, Steps step = LastStep) {
			if(auto resultPtr = d in processed) {
				return *resultPtr;
			}
			
			auto state = pass.state;
			scope(exit) pass.state = state;
			
			while(true) {
				if(auto resultPtr = d in processed) {
					return *resultPtr;
				}
				
				import sdc.terminal;
				outputCaretDiagnostics(state.declaration.location, state.declaration.toString() ~ " is waiting for...");
				outputCaretDiagnostics(d.location, d.toString());
				
				import std.stdio;
				writeln("Yield !");
				
				// Thread.sleep(dur!"seconds"(1));
				Fiber.yield();
			}
		}
		
		auto register(R)(Declaration source, R result) if(is(R : Symbol)) {
			processed[source] = result;
			
			if(source !is result) {
				processed[result] = result;
			}
			
			return result;
		}
		
		auto schedule(R)(R decls, ProcessDg dg) if(isDeclarationRange!R) {
			// Save state in order to restore it later.
			auto state = pass.state;
			scope(exit) pass.state = state;
			
			Process[] allTasks;
			foreach(decl; decls) {
				auto task = getProcess();
				task.init(decl, dg);
				
				pass.state = state;
				task.call();
				
				allTasks ~= task;
			}
			
			auto tasks = allTasks;
			void updateTasks() {
				auto oldTasks = tasks;
				tasks = [];
				
				foreach(t; oldTasks) {
					if(t.result) {
						register(t.source, t.result);
					} else {
						tasks ~= t;
					}
				}
			}
			
			updateTasks();
			while(tasks) {
				// TODO: update dependancy.
				import std.stdio;
				writeln("Yield (waiting for child to complete) !");
				
				// Thread.sleep(dur!"seconds"(1));
				Fiber.yield();
				
				foreach(t; tasks) {
					if(t.result is null) t.call();
				}
				
				updateTasks();
			}
			
			return allTasks.map!(p => p.result).array();
		}
	}
}

