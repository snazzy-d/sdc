module d.ast.conditional;

import d.ast.base;
import d.ast.declaration;
import d.ast.expression;
import d.ast.statement;

private template conditionalType(T) {
	static if(is(T == Statement)) {
		alias StatementType.Conditional conditionalType;
	} else static if(is(T == Declaration)) {
		alias DeclarationType.Conditional conditionalType;
	} else {
		static assert(false, "Conditional are only available for statements and declarations.");
	}
}

/**
 * Version Conditional
 */
class Version(ItemType) if(is(ItemType == Statement) || is(ItemType == Declaration)) : ItemType {
	string versionId;
	ItemType[] items;
	
	this(Location location, string versionId, ItemType[] items) {
		super(location, conditionalType!ItemType);
		
		this.versionId = versionId;
		this.items = items;
	}
}

/**
 * Version Conditional with else
 */
class VersionElse(ItemType) : Version!ItemType {
	ItemType[] elseItems;
	
	this(Location location, string versionId, ItemType[] items, ItemType[] elseItems) {
		super(location, versionId, items);
		
		this.elseItems = elseItems;
	}
}

/**
 * Version definition (ie version = FOOBAR)
 */
class VersionDefinition : Declaration {
	string versionId;
	
	this(Location location, string versionId) {
		super(location, DeclarationType.Conditional);
		
		this.versionId = versionId;
	}
}

/**
 * Debug ast alias
 */
alias Version Debug;
alias VersionElse DebugElse;
alias VersionDefinition DebugDefinition;

/**
 * Static if Conditional
 */
class StaticIf(ItemType) if(is(ItemType == Statement) || is(ItemType == Declaration)) : ItemType {
	Expression condition;
	ItemType[] items;
	
	this(Location location, Expression condition, ItemType[] items) {
		super(location, conditionalType!ItemType);
		
		this.condition = condition;
		this.items = items;
	}
}

/**
 * Static if Conditional with else
 */
class StaticIfElse(ItemType) : StaticIf!ItemType {
	ItemType[] elseItems;
	
	this(Location location, Expression condition, ItemType[] items, ItemType[] elseItems) {
		super(location, condition, items);
		
		this.elseItems = elseItems;
	}
}


