module d.semantic.flow;

import d.semantic.semantic;

import d.ir.instruction;

import d.context.location;

struct FlowAnalyzer {
private:
	SemanticPass pass;
	alias pass this;
	
	Body fbody;
	
	import d.ir.symbol;
	uint[Variable] closure;
	uint nextClosureIndex;
	
public:
	this(SemanticPass pass, Function f) in {
		assert(f.fbody, "f does not have a body");
	} body {
		this.pass = pass;
		
		fbody = f.fbody;
		nextClosureIndex = f.hasContext;
		foreach(p; f.params) {
			if (p.storage == Storage.Capture) {
				assert(p !in closure);
				closure[p] = nextClosureIndex++;
			}
		}
	}
	
	uint[Variable] getClosure() {
		foreach(b; range(fbody)) {
			visit(b);
		}
		
		return closure;
	}
	
	void visit(BasicBlockRef b) {
		auto instructions = range(fbody, b);
		foreach(i; instructions) {
			if (i.op != OpCode.Alloca) {
				continue;
			}
			
			auto v = i.var;
			if (v.storage == Storage.Capture) {
				assert(v !in closure);
				closure[v] = nextClosureIndex++;
			}
		}
	}
}
