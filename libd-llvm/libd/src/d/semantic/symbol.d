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

import d.ir.symbol;
import d.ir.type;

import std.algorithm;
import std.array;
import std.conv;

// TODO: change ast to allow any statement as function body, then remove that import.
import d.ast.statement;

alias FunctionType = d.ir.type.FunctionType;

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
		
		// Compute return type.
		if(typeid({ return fd.type.type.returnType; }()) !is typeid(AutoType)) {
			// TODO: Handle more fine grained types.
			f.type = pass.visit(QualAstType(fd.type.type));
			
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
			currentScope = f.dscope;
			
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
			/+
			case D :
				f.mangle = "_D" ~ manglePrefix ~ (f.isStatic?"F":"FM") ~ f.parameters.map!(p => (p.isReference?"K":"") ~ pass.typeMangler.visit(p.type)).join() ~ "Z" ~ typeMangler.visit(d.returnType);
				break;
			+/
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
	
	Variable visit(Variable d) {
		d.value = pass.visit(d.value);
		
		// If the type is infered, then we use the type of the value.
		// XXX: check for auto type in the declaration.
		if(/+cast(AutoType) d.type+/ false) {
			d.type = d.value.type;
		}
		
		d.value = buildImplicitCast(d.location, d.type, d.value);
		
		if(d.isEnum) {
			d.value = evaluate(d.value);
		}
		
		if(d.isStatic) {
			assert(d.linkage == Linkage.D, "I mangle only D !");
			d.mangle = "_D" ~ manglePrefix ~ to!string(d.name.length) ~ d.name ~ typeMangler.visit(d.type);
		}
		
		d.step = Step.Processed;
		return d;
	}
	
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
	
	Symbol visit(ClassDeclaration d) {
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
		
		currentScope = d.dscope = new SymbolScope(d, oldScope);
		thisType = new ClassType(d);
		
		// Update mangle prefix.
		manglePrefix = manglePrefix ~ to!string(d.name.length) ~ d.name;
		
		assert(d.linkage == "D");
		d.mangle = "C" ~ manglePrefix;
		
		FieldDeclaration[] baseFields;
		MethodDeclaration[] baseMethods;
		
		methodIndex = 0;
		if(d.mangle == "C6object6Object") {
			auto vtblType = pass.visit(new PointerType(new VoidType()));
			vtblType.qualifier = TypeQualifier.Immutable;
			baseFields = [new FieldDeclaration(d.location, 0, vtblType, "__vtbl", null)];
			
			fieldIndex = 1;
		} else {
			ClassDeclaration baseClass;
			foreach(ref base; d.bases) {
				auto type = cast(ClassType) pass.visit(base);
				assert(type, "Only classes are supported as base for now, " ~ typeid(type).toString() ~ " given.");
				
				base = type;
				baseClass = type.dclass;
				break;
			}
			
			if(!baseClass) {
				auto baseType = pass.visit(new BasicIdentifier(d.location, "Object")).apply!(function ClassType(parsed) {
					static if(is(typeof(parsed) : Type)) {
						return cast(ClassType) parsed;
					} else {
						return null;
					}
				})();
				
				assert(baseType, "Can't find object.Object");
				baseClass = baseType.dclass;
			}
			
			scheduler.require(baseClass);
			foreach(m; baseClass.members) {
				if(auto field = cast(FieldDeclaration) m) {
					baseFields ~= field;
					fieldIndex = max(fieldIndex, field.index);
					
					d.dscope.addSymbol(field);
				} else if(auto method = cast(MethodDeclaration) m) {
					baseMethods ~= method;
					methodIndex = max(methodIndex, method.index);
				}
			}
			
			fieldIndex++;
		}
		
		auto members = pass.flatten(d.members, d);
		
		d.step = Step.Signed;
		
		MethodDeclaration[] candidates = baseMethods;
		foreach(m; members) {
			if(auto method = cast(MethodDeclaration) m) {
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
				d.dscope.addOverloadableSymbol(candidate);
				baseMethods[i++] = candidate;
			}
		}
		
		d.members = cast(Declaration[]) baseFields;
		d.members ~= cast(Declaration[]) baseMethods;
		scheduler.require(members);
		d.members ~= cast(Declaration[]) members;
		
		d.step = Step.Processed;
		return d;
	}
	
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

