module d.ast.conditional;

import d.ast.base;
import d.ast.declaration;
import d.ast.expression;
import d.ast.statement;

/**
 * Version Conditional
 */
class Version(ItemType) if(is(ItemType == Statement) || is(ItemType == Declaration)) : ItemType {
	string versionId;
	ItemType[] items;
	
	this(Location location, string versionId, ItemType[] items) {
		super(location);
		
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
class VersionDefinition(ItemType) if(is(ItemType == Statement) || is(ItemType == Declaration)) : ItemType {
	string versionId;
	
	this(Location location, string versionId) {
		super(location);
		
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
		super(location);
		
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


