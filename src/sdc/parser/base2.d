module sdc.parser.base2;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;
import sdc.ast.declaration2;
import sdc.parser.declaration2;

auto parseModule(TokenStream tstream) {
	Declaration[] declarations;
	
	while(tstream.peek.type != TokenType.End) {
		declarations ~= parseDeclaration(tstream);
	}
	
	tstream.get();
	
	return null;
}

