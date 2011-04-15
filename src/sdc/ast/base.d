/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.base;

import std.algorithm;
import std.range;
import std.string;
import std.exception;

import sdc.compilererror;
import sdc.tokenstream;
import sdc.location;
import sdc.ast.attribute;


class Node
{
    Location location;
    Attribute[] attributes;
    
    /** 
     * Search the attributes list backwards for the first Linkage.
     * Returns: The last linkage, or Linkage.ExternD if no Linkage is found.
     */
    @property Linkage linkage()
    {
        static assert(AttributeType.Extern != AttributeType.init);
        
        AttributeType attributeType(Attribute attr) { return attr.type; }
        with (Linkage) { 
            auto linkages = [ExternC, ExternCPlusPlus, ExternD, ExternWindows, ExternPascal, ExternSystem]; 
            auto search = findAmong(retro(map!attributeType(attributes)), linkages);
            if (search.length > 0) {
                return enforce(cast(Linkage) search[0]);
            } else {
                return ExternD;
            }
        }  
    }
}

// ident(.ident)*
class QualifiedName : Node
{
    bool leadingDot = false;
    Identifier[] identifiers;
    
    QualifiedName dup()
    {
        auto qn = new QualifiedName();
        qn.identifiers = this.identifiers.dup;
        qn.leadingDot = this.leadingDot;
        return qn;
    }
}

class Identifier : Node
{
    string value;
}

class Literal : Node
{
}

class IntegerLiteral : Literal
{
    string value;
}

class FloatLiteral : Literal
{
    string value;
}

class CharacterLiteral : Literal
{
    string value;
}

class StringLiteral : Literal
{
    string value;
}

class ArrayLiteral : Literal
{
    Token[] tokens;
}

class AssocArrayLiteral : Literal
{
    Token[] tokens;
}

class FunctionLiteral : Literal
{
}
