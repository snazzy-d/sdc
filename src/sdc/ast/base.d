/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.base;


import sdc.compilererror;
import sdc.token;
import sdc.location;
import sdc.ast.attribute;

class Node
{
    Location location;
    Attribute[] attributes;
    Object userData;
    
    /** 
     * Search the attributes list backwards for the first Linkage.
     * Returns: The last linkage, or extern (D) if no Linkage is found.
     */
    Linkage linkage() @property pure
    {
        return cast(Linkage)searchAttributesBackwards(LINKAGES, AttributeType.ExternD);
    }
    
    /** 
     * Search the attributes list backwards for the first trust level.
     * Returns: The last trust level, or @system if no trust is found.
     */
    AttributeType trustLevel() @property pure
    {
        return searchAttributesBackwards(TRUSTLEVELS, AttributeType.atSystem);
    }
    
    /** 
     * Search the attributes list backwards for the first access level.
     * Returns: The last access level, or public if no access level is found.
     */
    Access access() @property pure
    {
        return cast(Access)searchAttributesBackwards(ACCESS, AttributeType.Public);
    }
    
    AttributeType searchAttributesBackwards(AttributeTypes contains,
                                            AttributeType _default) pure
    {
        foreach_reverse(attr; attributes)
            foreach(needle; contains)
                if (attr.type == needle)
                    return needle;
        return _default;
    }
    
    bool searchAttributesBackwards(AttributeType needle) pure
    {
        foreach_reverse(attr; attributes)
            if (attr.type == needle)
                return true;
        return false;
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
