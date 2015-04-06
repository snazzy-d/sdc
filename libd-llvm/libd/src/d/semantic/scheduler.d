module d.semantic.scheduler;

import d.ir.symbol;

import d.semantic.semantic;
import d.semantic.symbol;

import std.algorithm;
import std.range;
import std.traits;

import core.thread;

final class Scheduler {
	SemanticPass pass;
	
	Process[Symbol] processes;
	
	private Process[] pool;
	
	this(SemanticPass pass) {
		this.pass = pass;
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
		if (s.step >= step) return;
		
		auto state = pass.state;
		scope(exit) pass.state = state;
		
		while(s.step < step) {
			if (auto p = s in processes) {
				auto f = *p;
				if (f.state == Fiber.State.EXEC) {
					// TODO: Check for possible forward reference problem.
				}
				
				if (f.state == Fiber.State.HOLD) {
					f.call();
				}
				
				if (f.state == Fiber.State.TERM) {
					processes.remove(s);
					
					pool ~= f;
				}
			} else {
				assert(0, "Forward reference to " ~ s.name.toString(pass.context));
			}
			
			if (s.step >= step) return;
			/+
			import std.stdio;
			writeln(s.name.toString(pass.context), " ", step);
			/+
			try {
				throw new Exception("Require call stack");
			} catch(Exception e) {
				writeln(e);
			}
			// +/
			writeln("Yield !");
			
			Thread.sleep(dur!"seconds"(1));
			// +/
			Fiber.yield();
		}
	}
	
	void require(R)(R syms, Step step = LastStep) if(isSymbolRange!R) {
		foreach(s; syms) {
			require(s, step);
		}
	}
	
	private Process getProcess() {
		Process p;
		
		// XXX: it seems that if(pool) test for the pointer, not the content.
		// Seems to me like a weird conflation of identity and value.
		if(pool.length) {
			p = pool[$ - 1];
			
			pool = pool[0 .. $ - 1];
			pool.assumeSafeAppend();
		} else {
			p = new Process(pass);
		}
		
		return p;
	}
	
	void schedule(D, S)(D d, S s) if(isSchedulable!(D, S)) in {
		assert(s.step == SemanticPass.Step.Parsed, "Symbol processing already started.");
	} body {
		auto p = getProcess();
		p.init(d, s);
		
		processes[s] = p;
	}
	
	void schedule()(Template t, TemplateInstance i) in {
		assert(i.step == SemanticPass.Step.Parsed, "Symbol processing already started.");
	} body {
		auto p = getProcess();
		p.init(t, i);
		
		processes[i] = p;
	}
	
	// FIXME: We should consider a generic way to get things in there.
	// It is clearly not going to scale that way.
	import d.ast.expression;
	void schedule()(AstExpression dv, Variable v) in {
		assert(v.step == SemanticPass.Step.Parsed, "Symbol processing already started.");
	} body {
		auto p = getProcess();
		p.init(dv, v);
		
		processes[v] = p;
	}
}

private:
final class Process : Fiber {
	enum StackSize = 32 * 4096;
	
	SemanticPass pass;
	
	this(SemanticPass pass) {
		this.pass = pass;
		
		super(function() {
			assert(0, "You must initialize process before using it.");
		}, StackSize);
	}
	
	void init(D, S)(D d, S s) {
		auto state = pass.state;
		reset({
			pass.state = state;
			SymbolAnalyzer(pass).analyze(d, s);
		});
	}
}

alias Step = SemanticPass.Step;
enum LastStep = EnumMembers!Step[$ - 1];

bool checkEnumElements() {
	uint i;
	foreach(s; EnumMembers!Step) {
		if(s != i++) return false;
	}

	return i > 0;
}

static assert(is(Step : uint) && checkEnumElements(), "Step enum is ill defined.");

enum isSymbolRange(R) = isInputRange!R && is(ElementType!R : Symbol);

