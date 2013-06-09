module d.semantic.identifiable;

import d.ast.base;
import d.ast.type;
import d.ast.expression;
import d.ast.declaration;

/**
 * Tagged union that define something designed by an identifier.
 */
struct Identifiable {
	private Tag tag;
	
	private union {
		Type type;
		Expression expression;
		Symbol symbol;
	}
	
	@disable this();
	
	this(Type t) {
		tag = Tag.Type;
		type = t;
	}
	
	this(Expression e) {
		tag = Tag.Expression;
		expression = e;
	}
	
	this(Symbol s) {
		tag = Tag.Symbol;
		symbol = s;
	}
	
	invariant() {
		final switch(tag) {
			case Tag.Type :
				assert(type);
		 		break;
			
			case Tag.Expression :
				assert(expression);
				break;
			
			case Tag.Symbol :
				if(cast(TypeSymbol) symbol) {
					assert(0, "TypeSymbol must be resolved as Type.");
				} else if(cast(ExpressionSymbol) symbol) {
					assert(0, "ExpressionSymbol must be resolved as Expression.");
				}
				
				assert(symbol);
				break;
		}
	}
}

private enum Tag {
	Type,
	Expression,
	Symbol,
}

auto apply(alias handler)(Identifiable i) {
	final switch(i.tag) with(Tag) {
		case Type :
			return handler(i.type);
		
		case Expression :
			return handler(i.expression);
		
		case Symbol :
			return handler(i.symbol);
	}
}

