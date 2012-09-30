module d.parser.base;

import sdc.tokenstream;

public import sdc.location;
public import sdc.token;

import d.parser.dmodule;

auto parse(TokenRange)(ref TokenRange trange, string name, string[] packages) if(isTokenRange!TokenRange) {
	return trange.parseModule(name, packages);
}

template isTokenRange(T) {
	import std.range;
	
	enum isTokenRange = isForwardRange!T && is(ElementType!T : const(Token));
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

