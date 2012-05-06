module sdc.ast.conditional2;

import sdc.location;
import sdc.ast.declaration2;
import sdc.ast.statement2;

private template ConditionalType(ItemType) {
	static if(is(ItemType == Declaration)) {
		alias DeclarationStatement ConditionalType;
	} else static if(is(ItemType == Declaration)) {
		alias Statement ConditionalType;
	} else {
		static assert(false, "Invalid type provided : " ~ ItemType.stringof);
	}
}

/**
 * Version Conditional
 */
class Version(ItemType) : ConditionalType!ItemType {
	string versionId;
	ItemType[] items;
	
	this(Location location, string versionId, ItemType[] items) {
		super(location, DeclarationType.Conditional);
		
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
class VersionDefinition(ItemType) : ConditionalType!ItemType {
	string versionId;
	
	this(Location location, string versionId) {
		super(location, DeclarationType.Conditional);
		
		this.versionId = versionId;
	}
}

