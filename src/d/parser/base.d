// XXX: This whole file needs to go away.
module d.parser.base;

public import source.lexer;
public import source.context.location;

import source.context.name;

enum ParseMode {
	Greedy,
	Reluctant,
}

void match(ref TokenRange trange, TokenType type) {
	auto token = trange.front;
	
	if (token.type != type) {
		import std.conv, std.string;
		auto error = format("expected '%s', got '%s'.", to!string(type), to!string(token.type));
		
		import source.exception;
		throw new CompileException(token.location, error);
	}
	
	trange.popFront();
}
