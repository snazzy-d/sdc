/**
 * Entry point for the new multi-pass experiment.
 */
module sdc.sdc;

// TODO: move that into druntime.
// Ensure that null pointers are detected.
import etc.linux.memoryerror;

import std.stdio : writeln, stderr, stdout;
import std.file : exists;

import std.array;

import sdc.compilererror;
import sdc.lexer;
import sdc.source;
import sdc.tokenstream;

import d.parser.base;

int main(string[] args) {
	version(GC_CRASH) {
	} else {
		import core.memory;
		GC.disable();
	}

	if (args.length == 1) {
		stderr.writeln("usage: sdc file");
		return 1;
	}
	
	try {
		foreach (file; args[1..$]) {
			compile(file);
		}
	} catch(CompilerError e) {
		import sdc.terminal;
		outputCaretDiagnostics(e.location, e.msg);
		
		debug {
			import std.stdio;
			writeln(e.toString());
		}
		
		return 1;
	}
	
	return 0;
}

struct TokenRange {
	private const TokenStream tstream;
	private uint i;
	
	this(const TokenStream tstream) {
		this.tstream = tstream;
	}
	
	private this(const TokenStream tstream, uint i) {
		this.tstream = tstream;
		this.i = i;
	}
	
	// Disallow copy (save is made for that).
	// @disable
	// this(this);
	
	@property
	bool empty() const {
		return front.type == TokenType.End;
	}
	
	@property
	auto front() const {
		return tstream.lookahead(i);
	}
	
	void popFront() {
		i++;
	}
	
	@property
	auto save() const {
		return TokenRange(tstream, i);
	}
	
	auto opBinary(string op = "-")(ref const TokenRange rhs) const in {
		assert(tstream is rhs.tstream, "range must be comparable.");
	} body {
		return i - rhs.i;
	}
}

unittest {
	import d.parser.base;
	static assert(isTokenRange!TokenRange);
}

void compile(string filename) {
	auto trange = TokenRange(lex(new Source(filename)));
	auto object = TokenRange(lex(new Source("../libs/object.d")));
	
	auto packages = filename[0 .. $-2].split("/");
	auto ast = [object.parse("object", []), trange.parse(packages.back, packages[0 .. $-1])];
	
	// Test the new scheduler system.
	import d.semantic.semantic;
	import d.semantic.dscope;
	
	import d.backend.evaluator;
	import d.backend.llvm;
	auto backend	= new LLVMBackend(ast.back.location.filename);
	auto evaluator	= new LLVMEvaluator(backend.pass);
	
	auto semantic = new SemanticPass(evaluator);
	ast = semantic.process((new ScopePass()).visit(ast));
	
	import d.semantic.main;
	ast.back = buildMain(ast.back);
	
	//*
	backend.codeGen([ast.back]);
	//*/
}

