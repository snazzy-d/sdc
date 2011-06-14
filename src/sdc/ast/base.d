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

AttributeType attributeType(Attribute attr) { return attr.type; }

class Node
{
    Location location;
    Attribute[] attributes;
    
    /** 
     * Search the attributes list backwards for the first Linkage.
     * Returns: The last linkage, or extern (D) if no Linkage is found.
     */
    @property Linkage linkage()
    {
        with (AttributeType) {
            auto linkages = [ExternC, ExternCPlusPlus, ExternD, ExternWindows, ExternPascal, ExternSystem]; 
            return enforce(cast(Linkage) searchAttributesBackwards(linkages, ExternD));
        }
    }
    
    /** 
     * Search the attributes list backwards for the first trust level.
     * Returns: The last trust level, or @system if no trust is found.
     */
    @property AttributeType trustLevel()
    {
        with (AttributeType) return searchAttributesBackwards([atSafe, atTrusted, atSystem], atSystem);
    }
    
    /** 
     * Search the attributes list backwards for the first access level.
     * Returns: The last access level, or public if no access level is found.
     */
    @property Access access()
    {
        with (AttributeType) {
            auto access = [Private, Package, Protected, Public, Export];
            return enforce(cast(Access) searchAttributesBackwards(access, Public));
        }
    }
    
    AttributeType searchAttributesBackwards(AttributeType[] contains, AttributeType _default)
    {
        auto search = findAmong(retro(map!attributeType(attributes)), contains);
        if (search.length > 0) {
            return search[0];
        } else {
            return _default;
        } 
    }
    
    bool searchAttributesBackwards(AttributeType needle)
    {
        auto search = find(retro(map!attributeType(attributes)), needle);
        return search.length > 0;
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
