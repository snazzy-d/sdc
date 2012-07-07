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

