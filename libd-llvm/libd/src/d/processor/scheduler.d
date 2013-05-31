module d.processor.scheduler;

import d.ast.base;
import d.ast.declaration;

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
	enum isPass = is(typeof(P.init.state.symbol) : Symbol) && isPassEnum;
	
	static assert(isPass, "you can only schedule passes.");
	
	template isSymbolRange(R) {
		enum isSymbolRange = isInputRange!R && is(ElementType!R : Symbol);
	}
	
	struct Result {
		Symbol symbol;
		Step step;
	}
	
public:
	final class Scheduler {
		P pass;
		
		Result[Symbol] processed;
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
			
			assert(s !in processed, "You can't process the same item twice.");
			
			register(s, s, P.Step.Parsed);
			
			auto state = pass.state;
			p.init(s, (s) {
				pass.state = state;
				return dg(s);
			});
			
			processes[s] = p;
		}
		
		void terminate() {
			while(processes.length) {
				foreach(s; processes.keys) {
					require(s);
				}
			}
		}
		
		// TODO: refactor the duplicated check and return construct.
		private Result requireResult(Symbol s, Step step) {
			if(auto result = s in processed) {
				if(result.step >= step) {
					return *result;
				} else if(result.symbol !is s) {
					return processed[s] = requireResult(result.symbol, step);
				}
			}
			
			auto state = pass.state;
			scope(exit) pass.state = state;
			
			while(true) {
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
				
				if(auto result = s in processed) {
					if(result.step >= step) {
						return *result;
					} else if(result.symbol !is s) {
						return processed[s] = requireResult(result.symbol, step);
					}
				}
				
				// Thread.sleep(dur!"seconds"(1));
				Fiber.yield();
			}
		}
		
		// XXX: argument-less template. DMD don't allow overload of templated and non templated functions.
		auto require()(Symbol s, Step step = LastStep) {
			return requireResult(s, step).symbol;
		}
		
		auto require(R)(R syms, Step step = LastStep) if(isSymbolRange!R) {
			return syms.map!(s => require(s, step)).array();
		}
		
		auto register(S)(Symbol source, S symbol, Step step) if(is(S : Symbol)) in {
			if(auto r = source in processed) {
				import std.conv;
				assert(r.step < step, "Trying to register symbol at step " ~ to!string(step) ~ " when it is already registered at step " ~ to!string(r.step) ~ ".");
			}
		} body {
			auto result = Result(symbol, step);
			processed[source] = result;
			
			if(source !is symbol) {
				processed[symbol] = result;
			}
			
			return symbol;
		}
		
		auto schedule(R)(R syms, ProcessDg dg) if(isSymbolRange!R) {
			// Save state in order to restore it later.
			auto state = pass.state;
			scope(exit) pass.state = state;
			
			Process[] allTasks;
			foreach(s; syms.save) {
				runProcess(s, dg);
				
				pass.state = state;
			}
			
			return require(syms, P.Step.Parsed);
		}
	}
}

