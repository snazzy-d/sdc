module d.parser.base;

import sdc.tokenstream;

template isTokenRange(T) {
	import std.range;
	
	enum isTokenRange = isForwardRange!T && is(ElementType!T : const(Token));
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
	static assert(isTokenRange!TokenRange);
}

void match(TokenRange)(ref TokenRange trange, TokenType type) if(isTokenRange!TokenRange) {
	auto token = trange.front;
	
	if(token.type != type) {
		import sdc.compilererror;
		import std.conv, std.string;
		
		auto error = format("expected '%s', got '%s'.", tokenToString[type], token.value);
		
		import sdc.terminal;
		outputCaretDiagnostics(token.location, error);
		
		throw new CompilerError(token.location, error);
	}
	
	trange.popFront();
}

