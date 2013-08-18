module d.ast.conditional;

import d.ast.base;
import d.ast.declaration;
import d.ast.expression;
import d.ast.statement;

/**
 * Version Conditional
 */
class Version(ItemType) if(is(ItemType == AstStatement) || is(ItemType == Declaration)) : ItemType {
	string versionId;
	ItemType[] items;
	ItemType[] elseItems;
	
	this(Location location, string versionId, ItemType[] items, ItemType[] elseItems) {
		super(location);
		
		this.versionId = versionId;
		this.items = items;
		this.elseItems = elseItems;
	}
}

/**
 * Version definition (ie version = FOOBAR)
 */
class VersionDefinition(ItemType) if(is(ItemType == AstStatement) || is(ItemType == Declaration)) : ItemType {
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
alias VersionDefinition DebugDefinition;

/**
 * Static if Conditional
 */
class StaticIf(ItemType) if(is(ItemType == AstStatement) || is(ItemType == Declaration)) : ItemType {
	AstExpression condition;
	ItemType[] items;
	ItemType[] elseItems;
		
	this(Location location, AstExpression condition, ItemType[] items, ItemType[] elseItems) {
		super(location);
		
		this.condition = condition;
		this.items = items;
		this.elseItems = elseItems;
	}
}

/**
 * Mixins
 */
class Mixin(ItemType) if(is(ItemType == AstStatement) || is(ItemType == Declaration) || is(ItemType == Expression)) : ItemType {
	AstExpression value;
	
	this(Location location, AstExpression value) {
		super(location);
		
		this.value = value;
	}
}

