module d.parser.base;

import sdc.tokenstream;

template isTokenRange(T) {
	import std.range;
	
	enum isTokenRange = isForwardRange!T && is(ElementType!T : Token);
}

struct TokenRange {
	private TokenStream tstream;
	private uint i;
	
	this(TokenStream tstream) {
		this.tstream = tstream;
	}
	
	@property
	bool empty() {
		return front.type == TokenType.End;
	}
	
	@property
	Token front() {
		return tstream.lookahead(i);
	}
	
	void popFront() {
		i++;
	}
	
	@property
	TokenRange save() {
		return this;
	}
}

unittest {
	static assert(isTokenRange!TokenRange);
}

