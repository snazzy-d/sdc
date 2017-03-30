module d.ast.conditional;

import d.ast.declaration;
import d.ast.expression;
import d.ast.statement;

import d.context.location;

final:

/**
 * Version Conditional
 */
class Version(ItemType) : ItemType if (is(ItemType == Statement) || is(ItemType == Declaration))  {
	import d.context.name;
	Name versionId;
	
	ItemType[] items;
	ItemType[] elseItems;
	
	this(Location location, Name versionId, ItemType[] items, ItemType[] elseItems) {
		super(location);
		
		this.versionId = versionId;
		this.items = items;
		this.elseItems = elseItems;
	}
}

alias VersionDeclaration = Version!Declaration;

/**
 * Version definition (ie version = FOOBAR)
 */
class VersionDefinition(ItemType) : ItemType if(is(ItemType == Statement) || is(ItemType == Declaration)) {
	import d.context.name;
	Name versionId;
	
	this(Location location, Name versionId) {
		super(location);
		
		this.versionId = versionId;
	}
}

alias VersionDefinitionDeclaration = VersionDefinition!Declaration;

/**
 * Debug ast alias
 */
alias Debug = Version;
alias DebugDefinition = VersionDefinition;

/**
 * Static if Conditional
 */
class StaticIf(ItemType) : ItemType if(is(ItemType == Statement) || is(ItemType == Declaration)) {
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

alias StaticIfDeclaration = StaticIf!Declaration;

/**
 * Mixins
 */
class Mixin(ItemType) : ItemType if(is(ItemType == Statement) || is(ItemType == Declaration) || is(ItemType == AstExpression)) {
	AstExpression value;
	
	this(Location location, AstExpression value) {
		super(location);
		
		this.value = value;
	}
}

alias MixinDeclaration = Mixin!Declaration;

/**
 * Static assert
 */
class StaticAssert(ItemType) : ItemType if(is(ItemType == Statement) || is(ItemType == Declaration)) {
	AstExpression condition;
	AstExpression message;
	
	this(Location location, AstExpression condition, AstExpression message) {
		super(location);
		
		this.condition = condition;
		this.message = message;
	}
}
