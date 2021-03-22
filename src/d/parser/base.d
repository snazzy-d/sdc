// XXX: This whole file needs to go away.
module d.parser.base;

public import d.lexer;
public import d.context.location;

import d.context.name;

enum ParseMode {
	Greedy,
	Reluctant,
}

void match(ref TokenRange trange, TokenType type) {
	auto token = trange.front;
	
	if (token.type != type) {
		import std.conv, std.string;
		auto error = format("expected '%s', got '%s'.", to!string(type), to!string(token.type));
		
		import d.exception;
		throw new CompileException(token.location, error);
	}
	
	trange.popFront();
}
