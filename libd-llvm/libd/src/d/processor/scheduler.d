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
	
	this() {
		super({
			assert(0, "You must initialize process before using it.");
		});
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
		
		this(P pass) {
			this.pass = pass;
		}
		
		private void runProcess(Symbol s, ProcessDg dg) {
			/*
			if(pool) {
				auto ret = pool[$ - 1];
				
				pool = pool[0 .. $ - 1];
				pool.assumeSafeAppend();
				
				return ret;
			}
			*/
			assert(s !in processed, "You can't process the same item twice.");
			
			register(s, s, P.Step.Parsed);
			
			auto p = new Process();
			p.init(s, dg);
			
			p.call();
			
			if(p.state == Fiber.State.HOLD) {
				processes[s] = p;
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
					if(p.state == Fiber.State.EXEC) {
						// TODO: Check for possible forward reference problem.
					}
					
					if(p.state == Fiber.State.HOLD) {
						p.call();
					}
					
					if(p.state == Fiber.State.TERM) {
						processes.remove(s);
					}
				}
				
				if(auto result = s in processed) {
					if(result.step >= step) {
						return *result;
					} else if(result.symbol !is s) {
						return processed[s] = requireResult(result.symbol, step);
					}
				}
				
				import sdc.terminal;
				outputCaretDiagnostics(state.symbol.location, state.symbol.toString() ~ " is waiting for...");
				outputCaretDiagnostics(s.location, s.toString());
				
				import std.stdio;
				writeln("Yield !");
				
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
		
		auto register(S)(Symbol source, S symbol, Step step) if(is(S : Symbol)) {
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

