module d.semantic.identifiable;

import d.ast.base;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

/**
 * Tagged union that define something designed by an identifier.
 */
struct Identifiable {
	private Tag tag;
	
	private union {
		QualType type;
		Expression expression;
		Symbol symbol;
	}
	
	@disable this();
	
	this(QualType t) {
		tag = Tag.Type;
		type = t;
	}
	
	this(Type t) {
		this(QualType(t));
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
				assert(type.type);
		 		break;
			
			case Tag.Expression :
				assert(expression);
				break;
			
			case Tag.Symbol :
				if(cast(TypeSymbol) symbol) {
					assert(0, "TypeSymbol must be resolved as Type.");
				} else if(cast(ValueSymbol) symbol) {
					assert(0, "ExpressionSymbol must be resolved as Expression.");
				}
				
				assert(symbol);
				break;
		}
	}
}

unittest {
	static assert(Identifiable.init.tag == Tag.Symbol);
	static assert(Identifiable.init.symbol is null);
}

private enum Tag {
	Symbol,
	Type,
	Expression,
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

