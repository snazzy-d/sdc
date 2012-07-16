/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.base;


import sdc.compilererror;
import sdc.token;
import sdc.location;
import sdc.ast.attribute;
import sdc.ast.visitor;

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

    void accept(AstVisitor visitor)
    {
        //sassert(false);
    }
}

// ident(.ident)*
class QualifiedName : Node
{
    bool leadingDot = false;
    Identifier[] identifiers;
    
    QualifiedName dup() @property
    {
        auto qn = new QualifiedName();
        qn.identifiers = this.identifiers.dup;
        qn.leadingDot = this.leadingDot;
        return qn;
    }
    
    override bool opEquals(const Object o) const
    {
        if (auto other = cast(QualifiedName) o) {
            return identifiers == other.identifiers;
        } else {
            return false;
        }
    }

    override void accept(AstVisitor visitor)
    {
        foreach (ident; identifiers) {
            ident.accept(visitor);
        }
        visitor.visit(this);
    }
}

class Identifier : Node
{
    string value;

    override void accept(AstVisitor visitor)
    {
        visitor.visit(this);
    }
}

class Literal : Node
{
}

class IntegerLiteral : Literal
{
    string value;

    override void accept(AstVisitor visitor)
    {
        visitor.visit(this);
    }
}

class FloatLiteral : Literal
{
    string value;

    override void accept(AstVisitor visitor)
    {
        visitor.visit(this);
    }
}

class CharacterLiteral : Literal
{
    string value;

    override void accept(AstVisitor visitor)
    {
        visitor.visit(this);
    }
}

class StringLiteral : Literal
{
    string value;

    override void accept(AstVisitor visitor)
    {
        visitor.visit(this);
    }
}

class ArrayLiteral : Literal
{
    Token[] tokens;

    override void accept(AstVisitor visitor)
    {
        visitor.visit(this);
    }
}

class AssocArrayLiteral : Literal
{
    Token[] tokens;

    override void accept(AstVisitor visitor)
    {
        visitor.visit(this);
    }
}

class FunctionLiteral : Literal
{
    override void accept(AstVisitor visitor)
    {
        visitor.visit(this);
    }
}
