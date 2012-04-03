module sdc.ast.declaration2;

enum DeclarationType {
	Variable,
	Function,
/*	Template,
	Alias,
	AliasThis,
	Mixin,*/
}

interface Declaration {
	@property
	DeclarationType type();
}

