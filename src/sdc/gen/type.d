/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.type;

import std.string;

import sdc.compilererror;
import sdc.location;
import sdc.token;
import sdc.util;
import sdc.ast.declaration;
import sdc.gen.primitive;


enum Modifier
{
    Pointer,
}

enum DTypeType
{
    None,
    Bool = TokenType.Bool,
    Byte = TokenType.Byte,
    UByte = TokenType.Ubyte,
    Short = TokenType.Short,
    UShort = TokenType.Ushort,
    Int = TokenType.Int,
    UInt = TokenType.Uint,
    Long = TokenType.Long,
    ULong = TokenType.Ulong,
    Cent = TokenType.Cent,
    UCent = TokenType.Ucent,
    // TODO: Floating point, etc.
}


private void onImplicitCastFailure(DType from, DType to, Location at)
{
    error(at, format("cannot implicitly cast from type '%s' to type '%s'", from, to));
}

private void onExplicitCastFailure(DType from, DType to, Location at)
{
    error(at, format("cannot explicitly cast from type '%s' to type '%s'", from, to));
}

/// Convert a DTypeType to an actual DType instance.
DType createType(DTypeType dtype)
{
    final switch (dtype) {
    case DTypeType.None: throw new Exception("Cannot create DTypeType.None.");
    case DTypeType.Bool: return new BoolType();
    case DTypeType.Byte: return new ByteType();
    case DTypeType.UByte: return new UByteType();
    case DTypeType.Short: return new ShortType();
    case DTypeType.UShort: return new UShortType();
    case DTypeType.Int: return new IntType();
    case DTypeType.UInt: return new UIntType();
    case DTypeType.Long: return new LongType();
    case DTypeType.ULong: return new ULongType();
    case DTypeType.Cent: return new CentType();
    case DTypeType.UCent: return new UCentType();
    }
}

private DType iCast(DType from, DType to, Location at, DTypeType[] dtypes...)
{
    if (dtypes.contains(to.dtype)) {
        return createType(to.dtype);
    }
    onImplicitCastFailure(from, to, at);
    assert(false);
}

private DType eCast(DType from, DType to, Location at, DTypeType[] dtypes...)
{
    if (dtypes.contains(to.dtype)) {
        return createType(to.dtype);
    }
    onExplicitCastFailure(from, to, at);
    assert(false);
}

/**
 * DType is the bridge between the D and the backend's respective type
 * systems. DType handles both implicit and explicit casting between
 * types.
 * 
 * The idea is that a DType is defined in terms of the D type system
 * until the last possible moment.
 */
abstract class DType
{
    DTypeType dtype;
    Primitive primitive;
    
    /**
     * Attempt to implicitly cast this type to the given type.
     * Returns: the casted type.
     * Throws: CompilerError on failure.
     */
    DType implicitCast(DType to, Location at);
    
    /**
     * Attempt to explicitly cast this type to the given type.
     * Returns: the casted type.
     * Throws: CompilerError on failure.
     */
    DType explicitCast(DType to, Location at)
    {
        return createType(to.dtype);
    }
    
    void addModifier(Modifier modifier)
    {
        if (modifier == Modifier.Pointer) {
            primitive.pointer++;
            primitive.signed = false;
        }
        mModifiers ~= modifier;
    }
    
    Modifier[] modifiers() @property { return mModifiers; }
    
    
    protected Modifier[] mModifiers;
}

final class BoolType : DType
{
    this()
    {
        dtype = DTypeType.Bool;
        primitive.size = 1;
        primitive.signed = false;
    }
    
    override DType implicitCast(DType to, Location at)
    {
        return iCast(this, to, at, DTypeType.Bool, DTypeType.Byte, DTypeType.UByte,
                     DTypeType.Short, DTypeType.UShort, DTypeType.Int, DTypeType.UInt, 
                     DTypeType.Long, DTypeType.ULong, DTypeType.Cent, DTypeType.UCent);
    }
    
    override string toString()
    {
        return "bool";
    }
}

final class ByteType : DType
{
    this()
    {
        dtype = DTypeType.Byte;
        primitive.size = 8;
        primitive.signed = true;
    }
    
    override DType implicitCast(DType to, Location at)
    {
        return iCast(this, to, at, DTypeType.Bool, DTypeType.Byte, DTypeType.UByte,
                     DTypeType.Short, DTypeType.UShort, DTypeType.Int, DTypeType.UInt, 
                     DTypeType.Long, DTypeType.ULong, DTypeType.Cent, DTypeType.UCent);
    }
    
    override string toString()
    {
        return "byte";
    }
}

final class UByteType : DType
{
    this()
    {
        dtype = DTypeType.UByte;
        primitive.size = 8;
        primitive.signed = false;
    }
    
    override DType implicitCast(DType to, Location at)
    {
        return iCast(this, to, at, DTypeType.Bool, DTypeType.UByte,
                     DTypeType.Short, DTypeType.UShort, DTypeType.Int, DTypeType.UInt, 
                     DTypeType.Long, DTypeType.ULong, DTypeType.Cent, DTypeType.UCent);
    }
    
    override string toString()
    {
        return "ubyte";
    }
}

final class ShortType : DType
{
    this()
    {
        dtype = DTypeType.Short;
        primitive.size = 16;
        primitive.signed = true;
    }
    
    override DType implicitCast(DType to, Location at)
    {
        return iCast(this, to, at, DTypeType.Bool,
                     DTypeType.Short, DTypeType.UShort, DTypeType.Int, DTypeType.UInt, 
                     DTypeType.Long, DTypeType.ULong, DTypeType.Cent, DTypeType.UCent);
    }
    
    override string toString()
    {
        return "short";
    }
}

final class UShortType : DType
{
    this()
    {
        dtype = DTypeType.UShort;
        primitive.size = 16;
        primitive.signed = false;
    }
    
    override DType implicitCast(DType to, Location at)
    {
        return iCast(this, to, at, DTypeType.Bool,
                     DTypeType.UShort, DTypeType.Int, DTypeType.UInt, 
                     DTypeType.Long, DTypeType.ULong, DTypeType.Cent, DTypeType.UCent);
    }
    
    override string toString()
    {
        return "ushort";
    }
}

final class IntType : DType
{
    this()
    {
        dtype = DTypeType.Int;
        primitive.size = 32;
        primitive.signed = true;
    }
    
    override DType implicitCast(DType to, Location at)
    {
        return iCast(this, to, at, DTypeType.Bool, DTypeType.Int, DTypeType.UInt, 
                     DTypeType.Long, DTypeType.ULong, DTypeType.Cent, DTypeType.UCent);
    }
    
    override string toString()
    {
        return "int";
    }
}

final class UIntType : DType
{
    this()
    {
        dtype = DTypeType.UInt;
        primitive.size = 32;
        primitive.signed = false;
    }
    
    override DType implicitCast(DType to, Location at)
    {
        return iCast(this, to, at, DTypeType.Bool, DTypeType.UInt, 
                     DTypeType.Long, DTypeType.ULong, DTypeType.Cent, DTypeType.UCent);
    }
    
    override string toString()
    {
        return "uint";
    }
}

final class LongType : DType
{
    this()
    {
        dtype = DTypeType.Long;
        primitive.size = 64;
        primitive.signed = true;
    }
    
    override DType implicitCast(DType to, Location at)
    {
        return iCast(this, to, at, DTypeType.Bool,
                     DTypeType.Long, DTypeType.ULong, DTypeType.Cent, DTypeType.UCent);
    }
    
    override string toString()
    {
        return "long";
    }
}

final class ULongType : DType
{
    this()
    {
        dtype = DTypeType.ULong;
        primitive.size = 64;
        primitive.signed = false;
    }
    
    override DType implicitCast(DType to, Location at)
    {
        return iCast(this, to, at, DTypeType.Bool, 
                     DTypeType.ULong, DTypeType.Cent, DTypeType.UCent);
    }
    
    override string toString()
    {
        return "ulong";
    }
}

final class CentType : DType
{
    this()
    {
        dtype = DTypeType.Cent;
        primitive.size = 128;
        primitive.signed = true;
    }
    
    override DType implicitCast(DType to, Location at)
    {
        return iCast(this, to, at, DTypeType.Bool, DTypeType.Cent, DTypeType.UCent);
    }
    
    override string toString()
    {
        return "cent";
    }
}

final class UCentType : DType
{
    this()
    {
        dtype = DTypeType.UCent;
        primitive.size = 128;
        primitive.signed = false;
    }
    
    override DType implicitCast(DType to, Location at)
    {
        return iCast(this, to, at, DTypeType.Bool, DTypeType.UCent);
    }
    
    override string toString()
    {
        return "ucent";
    }
}
