module d.semantic.declaration;

import d.semantic.semantic;

import d.ast.conditional;
import d.ast.declaration;

import d.ir.dscope;
import d.ir.symbol;
import d.ir.type;

import std.algorithm;
import std.array;
import std.range;

alias Module = d.ir.symbol.Module;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

enum AggregateType {
	None,
	Union,
	Struct,
	Class,
}

enum AddContext {
	No,
	Yes,
}

struct DeclarationVisitor {
	private SemanticPass pass;
	alias pass this;
	
	alias Step = SemanticPass.Step;
	
	CtUnit[] ctUnits;
	ConditionalBranch[] cdBranches;
	
	private {
		import std.bitmanip;
		mixin(bitfields!(
			Linkage, "linkage", 3,
			Visibility, "visibility", 3,
			Storage, "storage", 2,
			AggregateType, "aggregateType", 2,
			AddContext, "addContext", 1,
			CtUnitLevel, "ctLevel", 2,
			bool, "isRef", 1,
			bool, "isOverride", 1,
			bool, "isAbstract", 1,
			bool, "isProperty", 1,
			bool, "isNoGC", 1,
			uint, "", 14,
		));
	}
	
	this(SemanticPass pass) {
		this.pass = pass;
		
		linkage = Linkage.D;
		visibility = Visibility.Public;
		storage = Storage.Local;
		aggregateType = AggregateType.None;
		addContext = AddContext.No;
		isOverride = false;
	}
	
	this(P...)(SemanticPass pass, P params) {
		this(pass);
		
		foreach(param; params) {
			alias T = typeof(param);
			
			static if(is(T == Linkage)) {
				linkage = param;
			} else static if(is(T == Visibility)) {
				visibility = param;
			} else static if(is(T == Storage)) {
				storage = param;
			} else static if(is(T == AggregateType)) {
				aggregateType = param;
			} else static if(is(T == AddContext)) {
				addContext = param;
			} else {
				// FIXME: horrible use of stringof. typeid(T) is not availabel at compile time :(
				static assert(0, T.stringof ~ " is not a valid initializer for DeclarationVisitor");
			}
		}
	}
	
	Symbol[] flatten(Declaration[] decls, Symbol parent) {
		auto ctus = flattenDecls(decls);
		parent.step = Step.Populated;
		
		auto dscope = currentScope;
		
		dscope.setPoisoningMode();
		scope(exit) {
			dscope.clearPoisoningMode();
		}
		
		return flatten(ctus)[0].symbols.map!(su => su.s).array();
	}
	
	Symbol[] flatten(Declaration d) {
		return flatten(flattenDecls([d]))[0].symbols.map!(su => su.s).array();
	}
	
	private auto flattenDecls(Declaration[] decls) {
		auto oldCtLevel = ctLevel;
		scope(exit) ctLevel = oldCtLevel;
		
		ctLevel = CtUnitLevel.Done;
		
		auto oldCtUnits = ctUnits;
		scope(exit) ctUnits = oldCtUnits;
		
		ctUnits = [CtUnit()];
		
		foreach(d; decls) {
			visit(d);
		}
		
		return ctUnits;
	}
	
	// At this point, CTFE can yield, and change object state,
	// so we pass things as parameters.
	private auto flatten(CtUnit[] ctus, CtUnitLevel to = CtUnitLevel.Done) {
		if(to == CtUnitLevel.Unknown) {
			return ctus;
		}
		
		// Process level 2 construct
		CtUnit[] cdUnits;
		cdUnits.reserve(ctus.length);
		foreach(u; ctus) {
			if(u.level == CtUnitLevel.Unknown) {
				final switch(u.type) with(CtUnitType) {
					case StaticIf :
						cdUnits ~= flattenStaticIf(u, CtUnitLevel.Conditional);
						break;
					
					case Mixin :
						cdUnits ~= flattenMixin(u, CtUnitLevel.Conditional);
						break;
					
					case Symbols :
						assert(0, "invalid ctUnit");
				}
			} else {
				cdUnits ~= u;
			}
		}
		
		if(to == CtUnitLevel.Conditional) {
			return cdUnits;
		}
		
		ctus = cdUnits;
		cdUnits = [];
		cdUnits.reserve(ctus.length);
		foreach(u; ctus) {
			if(u.level == CtUnitLevel.Conditional) {
				final switch(u.type) with(CtUnitType) {
					case StaticIf :
						cdUnits ~= flattenStaticIf(u, CtUnitLevel.Done);
						break;
					
					case Mixin :
					case Symbols :
						assert(0, "invalid ctUnit");
				}
			} else {
				assert(u.level == CtUnitLevel.Done);
				cdUnits ~= u;
			}
		}
		
		ctus = cdUnits[1 .. $];
		assert(cdUnits[0].level == CtUnitLevel.Done);
		
		foreach(u; ctus) {
			assert(u.level == CtUnitLevel.Done);
			assert(u.type == CtUnitType.Symbols);
			cdUnits[0].symbols ~= u.symbols;
		}
		
		return cdUnits[0 .. 1];
	}
	
	private auto flattenStaticIf(CtUnit unit, CtUnitLevel to) in {
		assert(unit.type == CtUnitType.StaticIf);
	} body {
		auto d = unit.staticIf;
		
		import d.ir.expression, d.semantic.caster, d.semantic.expression;
		auto condition = evalIntegral(buildExplicitCast(
			pass,
			d.condition.location,
			Type.get(BuiltinType.Bool),
			ExpressionVisitor(pass).visit(d.condition),
		));
		
		CtUnit[] items;
		if(condition) {
			currentScope.resolveConditional(d, true);
			items = unit.items;
		} else {
			currentScope.resolveConditional(d, false);
			items = unit.elseItems;
		}
		
		foreach(ref u; items) {
			if(u.type == CtUnitType.Symbols && u.level == CtUnitLevel.Conditional) {
				foreach(su; u.symbols) {
					import d.semantic.symbol;
					SymbolVisitor(pass).visit(su.d, su.s);
				}
				
				u.level = CtUnitLevel.Done;
			}
		}
		
		return flatten(items, to);
	}
	
	private auto flattenMixin(CtUnit unit, CtUnitLevel to) in {
		assert(unit.type == CtUnitType.Mixin);
	} body {
		auto d = unit.mixinDecl;

		import d.semantic.expression : ExpressionVisitor;
		auto str = evalString(ExpressionVisitor(pass).visit(d.value));
		
		// XXX: in order to avoid identifier resolution weirdness.
		auto location = d.location;
		
		import d.lexer, d.context.source, d.ir.expression;
		auto base = context.registerMixin(location, str ~ '\0');
		auto trange = lex(base, context);
		
		import d.parser.base;
		trange.match(TokenType.Begin);
		
		Declaration[] decls;
		while(trange.front.type != TokenType.End) {
			import d.parser.declaration;
			decls ~= trange.parseDeclaration();
		}
		
		return flatten(flattenDecls(decls), to);
	}
	
	void visit(Declaration d) {
		return this.dispatch(d);
	}
	
	private void select(D, S)(D d, S s) if(is(D : Declaration) && is(S : Symbol)) {
		auto unit = &(ctUnits[$ - 1]);
		assert(unit.type == CtUnitType.Symbols);
		
		if(unit.level == CtUnitLevel.Done) {
			scheduler.schedule(d, s);
		}
		
		unit.symbols ~= SymbolUnit(d, s);
	}
	
	void visit(FunctionDeclaration d) {
		auto stc = d.storageClass;
		auto storage = getStorage(stc);
		
		Function f;
		
		auto isStatic = storage.isNonLocal;
		if(isStatic || aggregateType != AggregateType.Class || d.name.isReserved) {
			f = new Function(d.location, FunctionType.init, d.name, [], null);
		} else {
			uint index = 0;
			if (!isOverride && !stc.isOverride) {
				index = ++methodIndex;
			}
			
			f = new Method(d.location, index, FunctionType.init, d.name, [], null);
		}
		
		f.linkage = getLinkage(stc);
		f.visibility = getVisibility(stc);
		f.storage = Storage.Enum;
		
		f.hasThis = isStatic ? false : aggregateType != AggregateType.None;
		f.hasContext = isStatic ? false : !!addContext;
		
		f.isAbstract = isAbstract || stc.isAbstract;
		f.isProperty = isProperty || stc.isProperty;
		
		addOverloadableSymbol(f);
		select(d, f);
	}
	
	void visit(VariableDeclaration d) {
		auto stc = d.storageClass;
		auto storage = getStorage(stc);
		
		Variable v;
		if (storage.isNonLocal || aggregateType == AggregateType.None) {
			v = new Variable(d.location, Type.get(BuiltinType.None), d.name);
		} else {
			v = new Field(d.location, fieldIndex, Type.get(BuiltinType.None), d.name);
			
			// Union have all their fields at the same index.
			if (aggregateType > AggregateType.Union) {
				fieldIndex++;
			}
		}
		
		v.linkage = getLinkage(stc);
		v.visibility = getVisibility(stc);
		v.storage = storage;
		
		addSymbol(v);
		select(d, v);
	}
	
	void visit(StructDeclaration d) {
		auto s = new Struct(d.location, d.name, []);
		s.linkage = linkage;
		s.visibility = visibility;
		s.storage = storage;
		
		s.hasContext = storage.isNonLocal ? false : !!addContext;
		
		addSymbol(s);
		select(d, s);
	}
	
	void visit(UnionDeclaration d) {
		auto u = new Union(d.location, d.name, []);
		u.linkage = linkage;
		u.visibility = visibility;
		u.storage = storage;
		
		u.hasContext = storage.isNonLocal ? false : !!addContext;
		
		addSymbol(u);
		select(d, u);
	}
	
	void visit(ClassDeclaration d) {
		auto c = new Class(d.location, d.name, []);
		c.linkage = linkage;
		c.visibility = visibility;
		c.storage = storage;
		
		c.hasContext = storage.isNonLocal ? false : !!addContext;
		
		addSymbol(c);
		select(d, c);
	}

	void visit(InterfaceDeclaration d) {
		auto i = new Interface(d.location, d.name, [], []);
		i.linkage = linkage;
		i.visibility = visibility;
		i.storage = storage; 

		addSymbol(i);
		select(d, i);
	}

	void visit(EnumDeclaration d) {
		if (d.name.isDefined) {
			auto e = new Enum(d.location, d.name, Type.get(BuiltinType.None), []);
			e.linkage = linkage;
			e.visibility = visibility;
			
			addSymbol(e);
			select(d, e);
		} else {
			// XXX: Code duplication with symbols. Refactor.
			import d.ast.expression : AstExpression, AstBinaryExpression;
			AstExpression previous;
			AstExpression one;
			foreach(vd; d.entries) {
				auto v = new Variable(vd.location, Type.get(BuiltinType.None), vd.name);
				v.visibility = visibility;
				
				if(!vd.value) {
					import d.ir.expression;
					if(previous) {
						if(!one) {
							one = new IntegerLiteral!true(vd.location, 1, BuiltinType.Int);
						}
						
						vd.value = new AstBinaryExpression(vd.location, BinaryOp.Add, previous, one);
					} else {
						vd.value = new IntegerLiteral!true(vd.location, 0, BuiltinType.Int);
					}
				}
				
				v.storage = Storage.Enum;
				previous = vd.value;
				
				addSymbol(v);
				select(vd, v);
			}
		}
	}
	
	void visit(TemplateDeclaration d) {
		auto t = new Template(d.location, d.name, [], d.declarations);
		
		t.linkage = linkage;
		t.visibility = visibility;
		t.storage = storage;
		
		addOverloadableSymbol(t);
		select(d, t);
	}
	
	void visit(IdentifierAliasDeclaration d) {
		auto a = new SymbolAlias(d.location, d.name, null);
		
		a.linkage = linkage;
		a.visibility = visibility;
		a.storage = Storage.Enum;
		
		addSymbol(a);
		select(d, a);
	}
	
	void visit(TypeAliasDeclaration d) {
		auto a = new TypeAlias(d.location, d.name, Type.get(BuiltinType.None));
		
		a.linkage = linkage;
		a.visibility = visibility;
		a.storage = Storage.Enum;
		
		addSymbol(a);
		select(d, a);
	}
	
	void visit(ValueAliasDeclaration d) {
		auto a = new ValueAlias(d.location, d.name, null);
		
		a.linkage = linkage;
		a.visibility = visibility;
		a.storage = Storage.Enum;
		
		addSymbol(a);
		select(d, a);
	}
	
	void visit(AliasThisDeclaration d) {
		assert(aggregateType != AggregateType.None, "alias this can only appear in aggregates.");
		
		// TODO: have a better scheme to do this in order to:
		// - keep the location of the alias for error messages.
		// - not redo identifier resolution all the time.
		auto as = cast(AggregateScope) currentScope;
		assert(as !is null, "Aggregate must have aggregate scope");
		
		as.aliasThis ~= d.name;
	}
	
	void visit(GroupDeclaration d) {
		auto oldStorage = storage;
		auto oldVisibility = visibility;
		auto oldLinkage = linkage;
		
		auto oldIsRef      = isRef;
		auto oldIsOverride = isOverride;
		auto oldIsAbstract = isAbstract;
		auto oldIsProperty = isProperty;
		auto oldIsNoGC     = isNoGC;
		
		scope(exit) {
			storage = oldStorage;
			visibility = oldVisibility;
			linkage = oldLinkage;
			
			isRef      = oldIsRef;
			isOverride = oldIsOverride;
			isAbstract = oldIsAbstract;
			isProperty = oldIsProperty;
			isNoGC     = oldIsNoGC;
		}
		
		auto stc = d.storageClass;
		
		storage = getStorage(stc);
		// qualifier = getQualifier(stc);
		visibility = getVisibility(stc);
		linkage = getLinkage(stc);
		
		isRef      = isRef      || stc.isRef;
		isOverride = isOverride || stc.isOverride;
		isAbstract = isAbstract || stc.isAbstract;
		isProperty = isProperty || stc.isProperty;
		isNoGC     = isNoGC     || stc.isNoGC;
		
		foreach(decl; d.declarations) {
			visit(decl);
		}
	}
	
	private Storage getStorage(StorageClass stc) {
		if (stc.isStatic && stc.isEnum) {
			assert(0, "cannot be static AND enum");
		} else if (stc.isStatic) {
			return Storage.Static;
		} else if (stc.isEnum) {
			return Storage.Enum;
		}
		
		return storage;
	}
	/+
	private TypeQualifier getQualifier(StorageClass stc) {
		return stc.hasQualifier
			? qualifier.add(stc.qualifier)
			: qualifier;
	}
	+/
	private Visibility getVisibility(StorageClass stc) {
		return stc.hasVisibility
			? stc.visibility
			: visibility;
	}
	
	private Linkage getLinkage(StorageClass stc) {
		return stc.hasLinkage
			? stc.linkage
			: linkage;
	}
	
	void visit(ImportDeclaration d) {
		Module[] addToScope;
		foreach(name; d.modules) {
			addToScope ~= importModule(name);
		}
		
		currentScope.imports ~= addToScope;
	}
	
	void visit(StaticIfDeclaration d) {
		auto finalCtLevel = CtUnitLevel.Conditional;
		auto oldCtLevel = ctLevel;
		scope(exit) ctLevel = max(finalCtLevel, oldCtLevel);
		
		ctLevel = CtUnitLevel.Conditional;
		
		auto finalCtUnits = ctUnits;
		scope(exit) ctUnits = finalCtUnits;
		
		auto unit = CtUnit();
		unit.type = CtUnitType.StaticIf;
		unit.staticIf = d;
		
		cdBranches ~= ConditionalBranch(d, true);
		scope(exit) {
			cdBranches = cdBranches[0 .. $ - 1];
		}
		
		ctUnits = [CtUnit()];
		ctUnits[0].level = CtUnitLevel.Conditional;
		
		foreach(item; d.items) {
			visit(item);
		}
		
		unit.items = ctUnits;
		
		finalCtLevel = max(finalCtLevel, ctLevel);
		ctLevel = CtUnitLevel.Conditional;
		
		cdBranches = cdBranches[0 .. $ - 1] ~ ConditionalBranch(d, false);
		
		ctUnits = [CtUnit()];
		ctUnits[0].level = CtUnitLevel.Conditional;
		
		foreach(item; d.elseItems) {
			visit(item);
		}
		
		unit.elseItems = ctUnits;
		
		finalCtLevel = max(finalCtLevel, ctLevel);
		unit.level = finalCtLevel;
		
		auto previous = finalCtUnits[$ - 1];
		assert(previous.type == CtUnitType.Symbols);
		
		auto next = CtUnit();
		next.level = previous.level;
		
		finalCtUnits ~= unit;
		finalCtUnits ~= next;
	}
	
	void visit(Version!Declaration d) {
		foreach(v; versions) {
			if(d.versionId == v) {
				foreach(item; d.items) {
					visit(item);
				}
				
				return;
			}
		}
		
		// Version has not been found.
		foreach(item; d.elseItems) {
			visit(item);
		}
	}
	
	void visit(Mixin!Declaration d) {
		ctLevel = CtUnitLevel.Unknown;
		
		auto unit = CtUnit();
		unit.level = CtUnitLevel.Unknown;
		unit.type = CtUnitType.Mixin;
		unit.mixinDecl = d;
		
		ctUnits ~= unit;
		ctUnits ~= CtUnit();
	}

private:
	void addSymbol(Symbol s) {
		if (cdBranches.length) {
			currentScope.addConditionalSymbol(s, cdBranches);
		} else {
			currentScope.addSymbol(s);
		}
	}

	void addOverloadableSymbol(Symbol s) {
		if (cdBranches.length) {
			currentScope.addConditionalSymbol(s, cdBranches);
		} else {
			currentScope.addOverloadableSymbol(s);
		}
	}
}

private :

enum CtUnitLevel {
	Done,
	Conditional,
	Unknown,
}

enum CtUnitType {
	Symbols,
	StaticIf,
	Mixin,
}

struct SymbolUnit {
	Declaration d;
	Symbol s;
}

struct CtUnit {
	import std.bitmanip;
	mixin(bitfields!(
		CtUnitLevel, "level", 2,
		CtUnitType, "type", 2,
		uint, "", 4,
	));
	
	union {
		SymbolUnit[] symbols;
		Mixin!Declaration mixinDecl;
		struct {
			// TODO: special declaration subtype here.
			StaticIfDeclaration staticIf;
			CtUnit[] items;
			CtUnit[] elseItems;
		};
	}
}

