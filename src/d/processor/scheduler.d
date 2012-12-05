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
	enum isPass = is(typeof(P.init.state.declaration) : Declaration) && isPassEnum;
	
	static assert(isPass, "you can only schedule passes.");
	
	template isDeclarationRange(R) {
		enum isDeclarationRange = isInputRange!R && is(ElementType!R : Declaration);
	}
	
	struct Result {
		Symbol symbol;
		Step step;
	}
	
public:
	final class Scheduler {
		P pass;
		
		Result[Declaration] processed;
		
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
		
		private Result requireResult(Declaration d, Step step) {
			if(auto result = d in processed) {
				if(result.step <= step) {
					return *result;
				} else if(result.symbol !is d) {
					return processed[d] = requireResult(result.symbol, step);
				}
			}
			
			auto state = pass.state;
			scope(exit) pass.state = state;
			
			while(true) {
				if(auto result = d in processed) {
					if(result.step <= step) {
						return *result;
					} else if(result.symbol !is d) {
						return processed[d] = requireResult(result.symbol, step);
					}
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
		
		auto require(Declaration d, Step step = LastStep) {
			return requireResult(d, step).symbol;
		}
		
		// TODO: remove the default value of step.
		auto register(S)(Declaration source, S symbol, Step step) if(is(S : Symbol)) {
			auto result = Result(symbol, step);
			processed[source] = result;
			
			if(source !is symbol) {
				processed[symbol] = result;
			}
			
			return symbol;
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
						register(t.source, t.result, LastStep);
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

