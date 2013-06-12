module d.semantic.symbol;

import d.semantic.identifiable;
import d.semantic.semantic;

import d.ast.adt;
import d.ast.dfunction;
import d.ast.declaration;
import d.ast.dscope;
import d.ast.dtemplate;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

import std.algorithm;
import std.array;
import std.conv;

// TODO: change ast to allow any statement as function body, then remove that import.
import d.ast.statement;

final class SymbolVisitor {
	private SemanticPass pass;
	alias pass this;
	
	alias SemanticPass.Step Step;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Symbol visit(Symbol s) {
		auto oldSymbol = symbol;
		scope(exit) symbol = oldSymbol;
		
		symbol = s;
		
		return this.dispatch(s);
	}
	
	Symbol visit(FunctionDeclaration d) {
		// XXX: May yield, but is only resolved within function, so everything depending on this declaration happen after.
		d.parameters = d.parameters.map!(p => pass.scheduler.register(p, this.dispatch(p), Step.Processed)).array();
		
		// Compute return type.
		if(typeid({ return d.returnType; }()) !is typeid(AutoType)) {
			d.returnType = pass.visit(d.returnType);
			
			// If it isn't a static method, add this.
			if(d.isStatic) {
				d.type = pass.visit(new FunctionType(d.linkage, d.returnType, d.parameters, d.isVariadic));
			} else {
				assert(thisType, "function must be static or thisType must be defined.");
				
				auto thisParameter = new Parameter(d.location, "this", thisType);
				thisParameter = pass.scheduler.register(thisParameter, this.dispatch(thisParameter), Step.Processed);
				thisParameter.isReference = isThisRef;
				
				d.type = pass.visit(new DelegateType(d.linkage, d.returnType, thisParameter, d.parameters, d.isVariadic));
			}
			
			scheduler.register(d, d, Step.Signed);
		}
		
		// Prepare statement visitor for return type.
		auto oldReturnType = returnType;
		auto oldManglePrefix = manglePrefix;
		scope(exit) {
			manglePrefix = oldManglePrefix;
			returnType = oldReturnType;
		}
		
		returnType = d.returnType;
		manglePrefix = manglePrefix ~ to!string(d.name.length) ~ d.name;
		
		if(d.fbody) {
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
			
			linkage = "D";
			
			isStatic = false;
			isOverride = false;
			buildFields = false;
			
			// Update scope.
			currentScope = d.dscope;
			
			// And visit.
			// TODO: change ast to allow any statement as function body;
			d.fbody = cast(BlockStatement) pass.visit(d.fbody);
		}
		
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
				
				auto thisParameter = new Parameter(d.location, "this", thisType);
				thisParameter = pass.scheduler.register(thisParameter, this.dispatch(thisParameter), Step.Processed);
				thisParameter.isReference = isThisRef;
				
				d.type = pass.visit(new DelegateType(d.linkage, d.returnType, thisParameter, d.parameters, d.isVariadic));
			}
		}
		
		switch(d.linkage) {
			case "D" :
				d.mangle = "_D" ~ manglePrefix ~ (d.isStatic?"F":"FM") ~ d.parameters.map!(p => (p.isReference?"K":"") ~ pass.typeMangler.visit(p.type)).join() ~ "Z" ~ typeMangler.visit(d.returnType);
				break;
			
			case "C" :
				d.mangle = d.name;
				break;
			
			default:
				assert(0, "Linkage " ~ d.linkage ~ " is not supported.");
		}
		
		scheduler.register(d, d, Step.Processed);
		
		return d;
	}
	
	Symbol visit(MethodDeclaration d) {
		return visit(cast(FunctionDeclaration) d);
	}
	
	Parameter visit(Parameter d) {
		d.type = pass.visit(d.type);
		
		return d;
	}
	
	VariableDeclaration visit(VariableDeclaration d) {
		d.value = pass.visit(d.value);
		
		// If the type is infered, then we use the type of the value.
		if(cast(AutoType) d.type) {
			d.type = d.value.type;
		} else {
			d.type = pass.visit(d.type);
		}
		
		d.value = buildImplicitCast(d.location, d.type, d.value);
		
		if(d.isEnum) {
			d.value = evaluate(d.value);
		}
		
		if(d.isStatic) {
			assert(d.linkage == "D");
			d.mangle = "_D" ~ manglePrefix ~ to!string(d.name.length) ~ d.name ~ typeMangler.visit(d.type);
		}
		
		scheduler.register(d, d, Step.Processed);
		
		return d;
	}
	
	Symbol visit(FieldDeclaration d) {
		// XXX: hacky ! We force CTFE that way.
		auto oldIsEnum = d.isEnum;
		scope(exit) d.isEnum = oldIsEnum;
		
		d.isEnum = true;
		
		return visit(cast(VariableDeclaration) d);
	}
	
	Symbol visit(AliasDeclaration d) {
		d.type = pass.visit(d.type);
		d.mangle = typeMangler.visit(d.type);
		
		scheduler.register(d, d, Step.Processed);
		
		return d;
	}
	
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
		
		fields = cast(FieldDeclaration[]) scheduler.require(fields);
		
		auto tuple = new TupleExpression(d.location, fields.map!(f => f.value).array());
		tuple.type = thisType;
		
		auto init = new VariableDeclaration(d.location, thisType, "init", tuple);
		init.isStatic = true;
		init.mangle = "_D" ~ manglePrefix ~ to!string(init.name.length) ~ init.name ~ d.mangle;
		
		d.dscope.addSymbol(init);
		scheduler.register(init, init, Step.Processed);
		
		scheduler.register(d, d, Step.Signed);
		
		d.members = [init];
		d.members ~= cast(Declaration[]) fields;
		d.members ~= cast(Declaration[]) scheduler.require(otherSymbols);
		
		scheduler.register(d, d, Step.Processed);
		
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
		
		scheduler.register(d, d, Step.Signed);
		
		MethodDeclaration[] candidates = baseMethods;
		foreach(m; members) {
			if(auto method = cast(MethodDeclaration) m) {
				method = cast(MethodDeclaration) scheduler.require(method, Step.Signed);
				if(method.index == 0) {
					foreach(ref candidate; candidates) {
						if(candidate && candidate.name == method.name && implicitCastFrom(method.type, candidate.type)) {
							method.index = candidate.index;
							candidate = null;
							break;
						}
					}
					
					if(method.index == 0) {
						assert(0, "Override not found for " ~ method.name);
					}
					
					continue;
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
		d.members ~= cast(Declaration[]) scheduler.require(members);
		
		scheduler.register(d, d, Step.Processed);
		
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
		
		scheduler.register(d, d, Step.Signed);
		
		scheduler.schedule(d.enumEntries, e => visit(e));
		scheduler.require(d.enumEntries);
		
		scheduler.register(d, d, Step.Processed);
		
		return d;
	}
	
	Symbol visit(TemplateDeclaration d) {
		// XXX: compute a proper mangling for templates.
		d.mangle = manglePrefix ~ to!string(d.name.length) ~ d.name;
		
		scheduler.register(d, d, Step.Processed);
		
		return d;
	}
}

