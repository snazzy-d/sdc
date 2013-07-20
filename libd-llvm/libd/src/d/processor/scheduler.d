module d.processor.scheduler;

// XXX: refactor.
import d.ast.base;
import d.ir.symbol;

import std.algorithm;
import std.range;
import std.traits;

import core.thread;

alias Symbol delegate(Symbol) ProcessDg;

final class Process : Fiber {
	Symbol source;
	Symbol result;
	
	enum StackSize = 32 * 4096;
	
	this() {
		super(function() {
			assert(0, "You must initialize process before using it.");
		}, StackSize);
	}
	
	void init(Symbol s, ProcessDg dg) {
		source = s;
		result = null;
		
		reset(delegate void() {
			result = dg(source);
		});
	}
}

template Scheduler(P) {
private:
	alias P.Step Step;
	enum LastStep = EnumMembers!Step[$ - 1];
	
	bool checkEnumElements() {
		uint i;
		foreach(s; EnumMembers!Step) {
			if(s != i++) return false;
		}
	
		return i > 0;
	}
	
	enum isPassEnum = is(Step : uint) && checkEnumElements();
	enum isPass = isPassEnum;
	
	static assert(isPass, "you can only schedule passes.");
	
	template isSymbolRange(R) {
		enum isSymbolRange = isInputRange!R && is(ElementType!R : Symbol);
	}
	
public:
	final class Scheduler {
		P pass;
		
		Process[Symbol] processes;
		
		private Process[] pool;
		
		this(P pass) {
			this.pass = pass;
		}
		
		private void runProcess(Symbol s, ProcessDg dg) {
			Process p;
			
			// XXX: it seems that if(pool) test for the pointer, not the content.
			// Seems to me like a weird conflation of identity and value.
			if(pool.length) {
				p = pool[$ - 1];
				
				pool = pool[0 .. $ - 1];
				pool.assumeSafeAppend();
			} else {
				p = new Process();
			}
			
			assert(s.step == P.Step.Parsed, "Symbol processing laready started.");
			
			auto state = pass.state;
			p.init(s, (s) {
				pass.state = state;
				return dg(s);
			});
			
			processes[s] = p;
		}
		
		void terminate() {
			auto f = new Fiber({
				while(processes.length) {
					foreach(s; processes.keys) {
						require(s);
					}
				}
			});
			
			while(f.state != Fiber.State.TERM) f.call();
		}
		
		// XXX: argument-less template. DMD don't allow overload of templated and non templated functions.
		void require()(Symbol s, Step step = LastStep) {
			if(s.step >= step) return;
			
			auto state = pass.state;
			scope(exit) pass.state = state;
			
			while(s.step < step) {
				if(auto p = s in processes) {
					auto f = *p;
					if(f.state == Fiber.State.EXEC) {
						// TODO: Check for possible forward reference problem.
					}
					
					if(f.state == Fiber.State.HOLD) {
						f.call();
					}
					
					if(f.state == Fiber.State.TERM) {
						processes.remove(s);
						
						pool ~= f;
					}
				}
				
				if(s.step >= step) return;
				
				// Thread.sleep(dur!"seconds"(1));
				import std.stdio;
				writeln("Yield !");
				Fiber.yield();
			}
		}
		
		void require(R)(R syms, Step step = LastStep) if(isSymbolRange!R) {
			foreach(s; syms) {
				require(s, step);
			}
		}
		
		void schedule(R)(R syms, ProcessDg dg) if(isSymbolRange!R) {
			// Save state in order to restore it later.
			auto state = pass.state;
			scope(exit) pass.state = state;
			
			Process[] allTasks;
			foreach(s; syms.save) {
				runProcess(s, dg);
				
				pass.state = state;
			}
		}
	}
}

