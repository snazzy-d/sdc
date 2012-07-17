/**
 * Entry point for the new multi-pass experiment.
 */
module sdc.mpsdc;

// TODO: move that into druntime.
// Ensure that null pointers are detected.
import util.nullpointererror;

import std.stdio : writeln, stderr, stdout;
import std.file : exists;

import sdc.compilererror;
import sdc.lexer;
import sdc.source;
import sdc.tokenstream;

import d.parser.base;

int main(string[] args) {
	if (args.length == 1) {
		stderr.writeln("usage: sdc file");
		return 1;
	}

	foreach (file; args[1..$]) {
		compile(file);
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
	auto src = new Source(filename);
	auto trange = TokenRange(lex(src));
	
	auto ast = trange.parse();
	
	
}

