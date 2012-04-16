/**
 * Copyright 2011 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.java.classformat;

import std.algorithm;
import std.array;
import std.file;


/**
 * read a big-endian formatted series of bytes from the given
 * ubyte array. The array is iterated to the first unread 
 * element. The length is set to zero when the end is reached.  
 */
private T eat(T)(ref ubyte[] file)
{
    if (file.length < T.sizeof) {
        badClass("file ended prematurely.");
    }
    
    auto slice = file[0 .. T.sizeof];
    file = file[T.sizeof .. $];
    size_t bitshift = (T.sizeof * 8) - 8, index = 0;
    T retval;
    while (index < slice.length) {
        retval |= slice[index] << bitshift;
        index++;
        bitshift -= 8;
    }
    return retval;
}

/**
 * Read a table of data from the given ubyte array. 
 *
 * The table is assumed to be preceded with a ushort length 
 * and this is where eatTable assumes the ubyte array to be. 
 */ 
private T[] eatTable(T)(ref ubyte[] file, size_t startIndex = 0)
{
    auto count = eat!ushort(file);
    auto table = new T[count];
    foreach (i; startIndex .. count) {
        static if (is(T : uint)) {
            table[i] = eat!T(file);
        } else {
            table[i] = new T(file);
        }
    }
    return table;
}

void badClass(string msg="")
{
    throw new Exception("not a class file: " ~ msg); 
}

class ClassFile
{
    ushort minorVersion;
    ushort majorVersion;
    ConstantPoolInfo[] constantPool;  // one indexed
    bool isPublic;
    bool isFinal;
    bool isSpecial;
    bool isInterface;
    bool isAbstract;
    ClassInfo thisClass;
    ClassInfo superClass;
    ClassInfo[] interfaces;
    FieldInfo[] fields;
    MethodInfo[] methods;
    AttributeInfo[] attributes;
    
    /// Parse the given class file.
    this(string fname)
    {
        auto file = cast(ubyte[]) std.file.read(fname);
        
        auto magic = eat!uint(file);
        if (magic != 0xCAFEBABE) {
            badClass("invalid magic number.");
        }
        
        minorVersion = eat!ushort(file);
        majorVersion = eat!ushort(file);
        
        constantPool = eatTable!ConstantPoolInfo(file, 1);
        
        auto accessFlags    = eat!ushort(file);
        isPublic       = cast(bool)(accessFlags & 0x0001);
        isFinal        = cast(bool)(accessFlags & 0x0010);
        isSpecial      = cast(bool)(accessFlags & 0x0020);
        isInterface    = cast(bool)(accessFlags & 0x0200);
        isAbstract     = cast(bool)(accessFlags & 0x0400);
        
        auto thisClassIndex = eat!ushort(file);
        thisClass = retrieve!ClassInfo(thisClassIndex);
        
        auto superClassIndex = eat!ushort(file);
        superClass = retrieve!ClassInfo(superClassIndex);
        
        auto interfaceIndices = eatTable!ushort(file);
        interfaces = new ClassInfo[interfaceIndices.length];
        foreach (i; interfaceIndices) {
            interfaces[i] = retrieve!ClassInfo(i);
        }
        
        fields = eatTable!FieldInfo(file);
        methods = eatTable!MethodInfo(file);
        attributes = eatTable!AttributeInfo(file);
        
        assert(file.length == 0);
    }
    
    MethodInfo[] nativeMethods()
    {
        MethodInfo[] native;
        foreach (method; methods) {
            if (cast(bool)(method.accessFlags & 0x0100)) {
                native ~= method;
            }
        }
        return native;
    }
    
    T retrieve(T)(size_t idx)
    {
        if (idx == 0 || idx >= constantPool.length) {
            badClass("invalid constant pool index.");
        }
        auto constant = constantPool[idx];
        
        with (ConstantType) {
            static if (is(T == ClassInfo)) {
                return constant.classInfo;
            } else if (is(T == FieldRefInfo)) {
                return constant.fieldRefInfo;
            } else if (is(T == MethodRefInfo)) {
                return constant.methodRefInfo;
            } else if (is(T == InterfaceMethodRefInfo)) {
                return constant.interfaceMethodRefInfo;
            } else if (is(T == StringInfo)) {
                return constant.stringInfo;
            } else if (is(T == IntegerInfo)) {
                return constant.integerInfo;
            } else if (is(T == FloatInfo)) {
                return constant.floatInfo;
            } else if (is(T == LongInfo)) {
                return constant.longInfo;
            } else if (is(T == DoubleInfo)) {
                return constant.doubleInfo;
            } else if (is(T == NameAndTypeInfo)) {
                return constant.nameAndTypeInfo;
            } else if (is(T == Utf8Info)) {
                return constant.utf8Info;
            } else if (is(T == UnicodeInfo)) {
                return constant.unicodeInfo;
            } else {
                static assert(false);
            }
        } 
    }
}

class ConstantPoolInfo
{
    ConstantType tag;
    union
    {
        MethodRefInfo methodRefInfo;
        FieldRefInfo fieldRefInfo;
        InterfaceMethodRefInfo interfaceMethodRefInfo;
        ClassInfo classInfo;
        StringInfo stringInfo;
        IntegerInfo integerInfo;
        FloatInfo floatInfo;
        LongInfo longInfo;
        DoubleInfo doubleInfo;
        NameAndTypeInfo nameAndTypeInfo;
        Utf8Info utf8Info;
        UnicodeInfo unicodeInfo;
    }
    
    this(ref ubyte[] file)
    {
        tag = cast(ConstantType) eat!ubyte(file);
        if (tag == 0) {
            badClass("invalid constant pool tag.");
        }
        final switch (tag) with (ConstantType) {
        case Class: classInfo = new ClassInfo(file); break;
        case Fieldref: fieldRefInfo = new FieldRefInfo(file); break;
        case Methodref: methodRefInfo = new MethodRefInfo(file); break;
        case InterfaceMethodref: interfaceMethodRefInfo = new InterfaceMethodRefInfo(file); break;
        case String: stringInfo = new StringInfo(file); break;
        case Integer: integerInfo = new IntegerInfo(file); break;
        case Float: floatInfo = new FloatInfo(file); break;
        case Long: longInfo = new LongInfo(file); break;
        case Double: doubleInfo = new DoubleInfo(file); break;
        case NameAndType: nameAndTypeInfo = new NameAndTypeInfo(file); break;
        case Utf8: utf8Info = new Utf8Info(file); break;
        case Unicode: unicodeInfo = new UnicodeInfo(file); break;
        }
    }
}
 
enum ConstantType : ubyte
{
    Class = 7,
    Fieldref = 9,
    Methodref = 10,
    InterfaceMethodref = 11,
    String = 8,
    Integer = 3,
    Float = 4,
    Long = 5,
    Double = 6,
    NameAndType = 12,
    Utf8 = 1,
    Unicode = 2
}

class MethodRefInfo
{
    ushort classIndex;
    ushort nameAndTypeIndex;
    
    this(ref ubyte[] file)
    {
        classIndex = eat!ushort(file);
        nameAndTypeIndex = eat!ushort(file);
    }
}

class FieldRefInfo
{
    ushort classIndex;
    ushort nameAndTypeIndex;
    
    this(ref ubyte[] file)
    {
        classIndex = eat!ushort(file);
        nameAndTypeIndex = eat!ushort(file);
    }
}

class InterfaceMethodRefInfo
{
    ushort classIndex;
    ushort nameAndTypeIndex;
    
    this(ref ubyte[] file)
    {
        classIndex = eat!ushort(file);
        nameAndTypeIndex = eat!ushort(file);
    }
}

class ClassInfo
{
    ushort index;
    
    this(ref ubyte[] file)
    {
        index = eat!ushort(file);
    }
}

class StringInfo
{
    ushort index;
    
    this(ref ubyte[] file)
    {
        index = eat!ushort(file);
    }
}

class IntegerInfo
{
    uint bytes;
    
    this(ref ubyte[] file)
    {
        bytes = eat!uint(file);
    }
}

class FloatInfo
{
    uint bytes;
    
    this(ref ubyte[] file)
    {
        bytes = eat!uint(file);
    }
}

class LongInfo
{
    uint highBytes;
    uint lowBytes;
    
    this(ref ubyte[] file)
    {
        highBytes = eat!uint(file);
        lowBytes = eat!uint(file);
    }
}

class DoubleInfo
{
    uint highBytes;
    uint lowBytes;
    
    this(ref ubyte[] file)
    {
        highBytes = eat!uint(file);
        lowBytes = eat!uint(file);
    }
}

class NameAndTypeInfo
{
    ushort nameIndex;
    ushort descriptorIndex;
    
    this(ref ubyte[] file)
    {
        nameIndex = eat!ushort(file);
        descriptorIndex = eat!ushort(file);
    }
}

class Utf8Info
{
    string str;
    
    this(ref ubyte[] file)
    {
        auto blength = eat!ushort(file);
        if (file.length < blength) {
            badClass("EOF reached in the middle of UTF-8 string.");
        }
        auto bytes = cast(char[]) file[0 .. blength];
        str = bytes.idup;
        file = file[blength .. $];
    }
    
    override string toString() { return str; }
}

class UnicodeInfo
{
    wstring str;
    
    this(ref ubyte[] file)
    {
        auto blength = eat!ushort(file);
        if (file.length < blength * 2) {
            badClass("EOF reached in the middle of a unicode string.");
        }
        auto bytes = new wchar[blength];
        foreach (i; 0 .. blength) {
            bytes[i] = cast(wchar) eat!ushort(file);
        }
        str = bytes.idup;
    }
}

class FieldInfo
{
    ushort accessFlags;
    ushort nameIndex;
    ushort descriptorIndex;
    AttributeInfo[] attributes;
    
    this(ref ubyte[] file)
    {
        accessFlags = eat!ushort(file);
        nameIndex = eat!ushort(file);
        descriptorIndex = eat!ushort(file);
        auto attributesCount = eat!ushort(file);
        attributes = new AttributeInfo[attributesCount];
        foreach (i; 0 .. attributesCount) {
            attributes[i] = new AttributeInfo(file);
        }
    }
}

class AttributeInfo
{
    ushort attributeNameIndex;
    ubyte[] info;
    
    this(ref ubyte[] file)
    {
        attributeNameIndex = eat!ushort(file);
        auto attributeLength = eat!uint(file);
        if (file.length < attributeLength) {
            badClass("EOF in AttributeInfo.");
        }
        info = file[0 .. attributeLength];
        file = file[attributeLength .. $];
    }
}

class MethodInfo
{
    ushort accessFlags;
    ushort nameIndex;
    ushort descriptorIndex;
    AttributeInfo[] attributes;
    
    this(ref ubyte[] file)
    {
        accessFlags = eat!ushort(file);
        nameIndex = eat!ushort(file);
        descriptorIndex = eat!ushort(file);
        
        auto attributesCount = eat!ushort(file);
        attributes = new AttributeInfo[attributesCount];
        foreach (i; 0 .. attributesCount) {
            attributes[i] = new AttributeInfo(file);
        }
    }
}
import std.stdio;
version (JavaTest) void main(string[] args)
{
    auto classfile = new ClassFile(args[1]);
    
    writefln("class %s defines native method(s):", classfile.constantPool[classfile.thisClass.index].utf8Info);
    auto native = classfile.nativeMethods();
    foreach (nmethod; native) {
        auto name = classfile.constantPool[nmethod.nameIndex].utf8Info;
        writeln("  ", name);
    }
}
