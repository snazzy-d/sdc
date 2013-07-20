module d.semantic.symbol;

import d.semantic.identifiable;
import d.semantic.semantic;

import d.ast.base;
import d.ast.dfunction;
import d.ast.declaration;
import d.ast.dtemplate;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

import d.ir.dscope;
import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import std.algorithm;
import std.array;
import std.conv;

// TODO: change ast to allow any statement as function body, then remove that import.
import d.ast.statement;

alias FunctionType = d.ir.type.FunctionType;
alias PointerType = d.ir.type.PointerType;

final class SymbolVisitor {
	private SemanticPass pass;
	alias pass this;
	
	alias SemanticPass.Step Step;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Symbol visit(Declaration d, Symbol s) {
		return this.dispatch(d, s);
	}
	
	Symbol visit(Symbol s) {
		return this.dispatch(s);
	}
	
	Symbol visit(Declaration d, Function f) {
		auto fd = cast(FunctionDeclaration) d;
		assert(fd);
		
		// XXX: maybe monad ?
		auto params = f.params = fd.params.map!(p => new Parameter(p.location, pass.visit(p.type), p.name, p.value?(pass.visit(p.value)):null)).array();
		
		// Compute return type.
		if(typeid({ return fd.returnType.type; }()) !is typeid(AutoType)) {
			// TODO: Handle more fine grained types.
			/*
			f.type = pass.visit(QualAstType(fd.type.type));
			auto funType = cast(FunctionType) f.type.type;
			
			assert(funType);
			*/
			
			// If it isn't a static method, add this.
			if(!f.isStatic) {
				assert(0);
				/+
				assert(thisType, "function must be static or thisType must be defined.");
				
				auto thisParameter = this.dispatch(new Parameter(d.location, "this", thisType));
				thisParameter.isReference = isThisRef;
				
				d.type = pass.visit(new DelegateType(d.linkage, d.returnType, thisParameter, d.parameters, d.isVariadic));
				+/
			}
			
			// XXX: completely hacked XD
			f.type = QualType(new FunctionType(Linkage.D, pass.visit(fd.returnType), params.map!(p => p.pt).array(), fd.isVariadic));
			
			f.step = Step.Signed;
		}
		
		// Prepare statement visitor for return type.
		auto oldReturnType = returnType;
		auto oldManglePrefix = manglePrefix;
		scope(exit) {
			manglePrefix = oldManglePrefix;
			returnType = oldReturnType;
		}
		
		returnType = (cast(FunctionType) f.type.type).returnType;
		manglePrefix = manglePrefix ~ to!string(f.name.length) ~ f.name;
		
		if(f.fbody) {
			auto oldLinkage = linkage;
			auto oldIsStatic = isStatic;
			auto oldIsOverride = isOverride;
			auto oldBuildFields = buildFields;
			auto oldScope = currentScope;
			
			scope(exit) {
				linkage = oldLinkage;
				isStatic = oldIsStatic;
				isOverride = oldIsOverride;
				buildFields = oldBuildFields;
				currentScope = oldScope;
			}
			
			linkage = Linkage.D;
			
			isStatic = false;
			isOverride = false;
			buildFields = false;
			
			// Update scope.
			currentScope = f.dscope = new NestedScope(oldScope);
			
			// Register parameters.
			foreach(p; params) {
				f.dscope.addSymbol(p);
			}
			
			// And visit.
			// TODO: change ast to allow any statement as function body;
			f.fbody = cast(BlockStatement) pass.visit(f.fbody);
		}
		/+
		if(typeid({ return d.returnType; }()) is typeid(AutoType)) {
			// Should be useless once return type inference is properly implemented.
			if(typeid({ return pass.returnType; }()) is typeid(AutoType)) {
				assert(0, "can't infer return type");
			}
			
			d.returnType = returnType;
			
			// If it isn't a static method, add this.
			// TODO: Duplicated, find a way to solve that.
			if(d.isStatic) {
				d.type = pass.visit(new FunctionType(d.linkage, d.returnType, d.parameters, d.isVariadic));
			} else {
				assert(thisType, "function must be static or thisType must be defined.");
				
				auto thisParameter = this.dispatch(new Parameter(d.location, "this", thisType));
				thisParameter.isReference = isThisRef;
				
				d.type = pass.visit(new DelegateType(d.linkage, d.returnType, thisParameter, d.parameters, d.isVariadic));
			}
		}
		+/
		switch(f.linkage) with(Linkage) {
			case D :
				auto typeMangle = pass.typeMangler.visit(f.type);
				f.mangle = "_D" ~ manglePrefix ~ (f.isStatic?typeMangle:("FM" ~ typeMangle[1 .. $]));
				break;
			
			case C :
				f.mangle = f.name;
				break;
			
			default:
				import std.conv;
				assert(0, "Linkage " ~ to!string(f.linkage) ~ " is not supported.");
		}
		
		f.step = Step.Processed;
		return f;
	}
	
	Symbol visit(Method d) {
		return visit(cast(Function) d);
	}
	/+
	Parameter visit(Parameter d) {
		d.type = pass.visit(d.type);
		
		d.step = Step.Processed;
		return d;
	}
	+/
	Variable visit(Declaration d, Variable v) {
		auto vd = cast(VariableDeclaration) d;
		assert(vd);
		
		Expression value;
		if(typeid({ return vd.type.type; }()) is typeid(AutoType)) {
			value = pass.visit(vd.value);
			v.type = value.type;
		} else {
			auto type = v.type = pass.visit(vd.type);
			value = vd.value
				? pass.visit(vd.value)
				: defaultInitializerVisitor.visit(v.location, type);
			value = buildImplicitCast(d.location, type, value);
		}
		
		if(v.isEnum) {
			value = evaluate(value);
		}
		
		v.value = value;
		
		if(v.isStatic) {
			assert(v.linkage == Linkage.D, "I mangle only D !");
			v.mangle = "_D" ~ manglePrefix ~ to!string(v.name.length) ~ v.name ~ typeMangler.visit(v.type);
		}
		
		v.step = Step.Processed;
		return v;
	}
	/+
	Symbol visit(Field d) {
		// XXX: hacky ! We force CTFE that way.
		auto oldIsEnum = d.isEnum;
		scope(exit) d.isEnum = oldIsEnum;
		
		d.isEnum = true;
		
		return visit(cast(Variable) d);
	}
	+/
	Symbol visit(Declaration d, TypeAlias a) {
		auto ad = cast(AliasDeclaration) d;
		assert(ad);
		
		a.type = pass.visit(ad.type);
		a.mangle = typeMangler.visit(a.type);
		
		a.step = Step.Processed;
		return a;
	}
	/+
	Symbol visit(StructDeclaration d) {
		auto oldIsStatic = isStatic;
		auto oldIsOverride = isOverride;
		auto oldManglePrefix = manglePrefix;
		auto oldScope = currentScope;
		auto oldThisType = thisType;
		auto oldIsThisRef = isThisRef;
		auto oldBuildFields = buildFields;
		auto oldBuildMethods = buildMethods;
		auto oldFieldIndex = fieldIndex;
		
		scope(exit) {
			isStatic = oldIsStatic;
			isOverride = oldIsOverride;
			manglePrefix = oldManglePrefix;
			currentScope = oldScope;
			thisType = oldThisType;
			isThisRef = oldIsThisRef;
			buildFields = oldBuildFields;
			buildMethods = oldBuildMethods;
			fieldIndex = oldFieldIndex;
		}
		
		isStatic = false;
		isOverride = false;
		isThisRef = true;
		buildFields = true;
		buildMethods = false;
		
		currentScope = d.dscope = new SymbolScope(d, oldScope);
		thisType = new StructType(d);
		
		// Update mangle prefix.
		manglePrefix = manglePrefix ~ to!string(d.name.length) ~ d.name;
		
		assert(d.linkage == "D");
		d.mangle = "S" ~ manglePrefix;
		
		fieldIndex = 0;
		
		auto members = pass.flatten(d.members, d);
		
		FieldDeclaration[] fields;
		auto otherSymbols = members.filter!((m) {
			if(auto f = cast(FieldDeclaration) m) {
				fields ~= f;
				return false;
			}
			
			return true;
		}).array();
		
		scheduler.require(fields);
		
		auto tuple = new TupleExpression(d.location, fields.map!(f => f.value).array());
		tuple.type = thisType;
		
		auto init = new VariableDeclaration(d.location, thisType, "init", tuple);
		init.isStatic = true;
		init.mangle = "_D" ~ manglePrefix ~ to!string(init.name.length) ~ init.name ~ d.mangle;
		
		d.dscope.addSymbol(init);
		init.step = Step.Processed;
		
		d.step = Step.Signed;
		
		d.members = [init];
		d.members ~= cast(Declaration[]) fields;
		scheduler.require(otherSymbols);
		d.members ~= cast(Declaration[]) otherSymbols;
		
		d.step = Step.Processed;
		return d;
	}
	+/
	Symbol visit(Declaration d, Class c) {
		auto cd = cast(ClassDeclaration) d;
		assert(cd);
		
		auto oldIsStatic = isStatic;
		auto oldIsOverride = isOverride;
		auto oldManglePrefix = manglePrefix;
		auto oldScope = currentScope;
		auto oldThisType = thisType;
		auto oldIsThisRef = isThisRef;
		auto oldBuildFields = buildFields;
		auto oldBuildMethods = buildMethods;
		auto oldFieldIndex = fieldIndex;
		auto oldMethodIndex = methodIndex;
		
		scope(exit) {
			isStatic = oldIsStatic;
			isOverride = oldIsOverride;
			manglePrefix = oldManglePrefix;
			currentScope = oldScope;
			thisType = oldThisType;
			isThisRef = oldIsThisRef;
			buildFields = oldBuildFields;
			buildMethods = oldBuildMethods;
			fieldIndex = oldFieldIndex;
			methodIndex = oldMethodIndex;
		}
		
		isStatic = false;
		isOverride = false;
		isThisRef = false;
		buildFields = true;
		buildMethods = true;
		
		currentScope = c.dscope = new SymbolScope(c, oldScope);
		thisType = QualType(new ClassType(c));
		
		// Update mangle prefix.
		manglePrefix = manglePrefix ~ to!string(c.name.length) ~ c.name;
		
		c.mangle = "C" ~ manglePrefix;
		
		Field[] baseFields;
		Method[] baseMethods;
		
		methodIndex = 0;
		if(c.mangle == "C6object6Object") {
			auto vtblType = QualType(new PointerType(getBuiltin(TypeKind.Void)));
			vtblType.qualifier = TypeQualifier.Immutable;
			
			// TODO: use defaultinit.
			auto vtbl = new Field(cd.location, 0, vtblType, "__vtbl", null);
			vtbl.step = Step.Processed;
			
			baseFields = [vtbl];
			
			fieldIndex = 1;
		} else {
			Class baseClass;
			foreach(base; cd.bases) {
				auto type = pass.visit(base).apply!(function ClassType(identified) {
					static if(is(typeof(identified) : QualType)) {
						return cast(ClassType) identified.type;
					} else {
						return null;
					}
				})();
				
				assert(type, "Only classes are supported as base for now, " ~ typeid(type).toString() ~ " given.");
				
				baseClass = type.dclass;
				break;
			}
			
			if(!baseClass) {
				auto baseType = pass.visit(new BasicIdentifier(d.location, "Object")).apply!(function ClassType(parsed) {
					static if(is(typeof(parsed) : QualType)) {
						return cast(ClassType) parsed.type;
					} else {
						return null;
					}
				})();
				
				assert(baseType, "Can't find object.Object");
				baseClass = baseType.dclass;
			}
			
			scheduler.require(baseClass);
			foreach(m; baseClass.members) {
				if(auto field = cast(Field) m) {
					baseFields ~= field;
					fieldIndex = max(fieldIndex, field.index);
					
					c.dscope.addSymbol(field);
				} else if(auto method = cast(Method) m) {
					baseMethods ~= method;
					methodIndex = max(methodIndex, method.index);
				}
			}
			
			fieldIndex++;
		}
		
		auto members = pass.flatten(cd.members, c);
		
		c.step = Step.Signed;
		
		Method[] candidates = baseMethods;
		foreach(m; members) {
			if(auto method = cast(Method) m) {
				scheduler.require(method, Step.Signed);
				foreach(ref candidate; candidates) {
					if(candidate && candidate.name == method.name && implicitCastFrom(method.type, candidate.type)) {
						if(method.index == 0) {
							method.index = candidate.index;
							candidate = null;
							break;
						} else {
							assert(0, "Override not marked as override !");
						}
					}
				}
				
				if(method.index == 0) {
					assert(0, "Override not found for " ~ method.name);
				}
			}
		}
		
		// Remaining candidates must be added to scope.
		baseMethods.length = candidates.length;
		uint i = 0;
		foreach(candidate; candidates) {
			if(candidate) {
				c.dscope.addOverloadableSymbol(candidate);
				baseMethods[i++] = candidate;
			}
		}
		
		c.members = cast(Symbol[]) baseFields;
		c.members ~= baseMethods;
		scheduler.require(members);
		c.members ~= members;
		
		c.step = Step.Processed;
		return c;
	}
	/+
	Symbol visit(EnumDeclaration d) {
		assert(d.name, "anonymous enums must be flattened !");
		
		auto oldIsStatic = isStatic;
		scope(exit) isStatic = oldIsStatic;
		
		isStatic = true;
		
		d.type = pass.visit(d.type);
		auto type = new EnumType(d);
		
		if(typeid({ return d.type; }()) !is typeid(IntegerType)) {
			assert(0, "enum are of integer type.");
		}
		
		// Update mangle prefix.
		auto oldManglePrefix = manglePrefix;
		scope(exit) manglePrefix = oldManglePrefix;
		
		manglePrefix = manglePrefix ~ to!string(d.name.length) ~ d.name;
		
		assert(d.linkage == "D");
		d.mangle = "E" ~ manglePrefix;
		
		VariableDeclaration previous;
		foreach(e; d.enumEntries) {
			e.isEnum = true;
			
			if(typeid({ return e.value; }()) is typeid(DefaultInitializer)) {
				if(previous) {
					e.value = new AddExpression(e.location, new SymbolExpression(e.location, previous), makeLiteral(e.location, 1));
				} else {
					e.value = makeLiteral(e.location, 0);
				}
			}
			
			e.value = new CastExpression(e.location, type, e.value);
			e.type = type;
			
			previous = e;
		}
		
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = d.dscope = new SymbolScope(d, oldScope);
		
		foreach(e; d.enumEntries) {
			d.dscope.addSymbol(e);
		}
		
		d.step = Step.Signed;
		
		scheduler.schedule(d.enumEntries, e => visit(e));
		scheduler.require(d.enumEntries);
		
		d.step = Step.Processed;
		return d;
	}
	
	Symbol visit(TemplateDeclaration d) {
		// XXX: compute a proper mangling for templates.
		d.mangle = manglePrefix ~ to!string(d.name.length) ~ d.name;
		
		d.step = Step.Processed;
		return d;
	}
	+/
}

