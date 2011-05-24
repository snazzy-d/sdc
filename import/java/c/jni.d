module java.c.jni;
extern (C):

import core.vararg;


alias int jint;
alias long jlong;
alias byte jbyte;
alias jint jsize;
alias ubyte jboolean;
alias ushort jchar;
alias short jshort;
alias float jfloat;
alias double jdouble;

struct _jobject;
alias _jobject* jobject;
alias jobject jclass;
alias jobject jthrowable;
alias jobject jstring;
alias jobject jarray;
alias jarray jbooleanArray;
alias jarray jbyteArray;
alias jarray jcharArray;
alias jarray jshortArray;
alias jarray jintArray;
alias jarray jlongArray;
alias jarray jfloatArray;
alias jarray jdoubleArray;
alias jarray jobjectArray;
alias jobject jweak;

union jvalue {
    jboolean z;
    jbyte    b;
    jchar    c;
    jshort   s;
    jint     i;
    jlong    j;
    jfloat   f;
    jdouble  d;
    jobject  l;
}

struct _jfieldID;
alias _jfieldID *jfieldID;

struct _jmethodID;
alias _jmethodID *jmethodID;

enum jobjectRefType {
     JNIInvalidRefType    = 0,
     JNILocalRefType      = 1,
     JNIGlobalRefType     = 2,
     JNIWeakGlobalRefType = 3 
}

enum JNI_FALSE = 0;
enum JNI_TRUE = 1;

enum 
{
    JNI_OK = 0,
    JNI_ERR = -1,
    JNI_EDETACHED = -2,
    JNI_EVERSION = -3,
    JNI_ENOMEM = -4,
    JNI_EEXIST = -5,
    JNI_EINVAL = -6,
}

enum JNI_COMMIT = 1;
enum JNI_ABORT = 2;

struct JNINativeMethod {
    char *name;
    char *signature;
    void *fnPtr;
} 

alias JNINativeInterface_ *JNIEnv;
alias JNIInvokeInterface_ *JavaVM;

struct JNINativeInterface_ {
    void *reserved0;
    void *reserved1;
    void *reserved2;

    void *reserved3;
    jint function(JNIEnv* env) GetVersion;

    jclass function(JNIEnv *env, const(char)* name, jobject loader, const jbyte *buf,
       jsize len) DefineClass;
    jclass function(JNIEnv *env, const(char)* name) FindClass;

    jmethodID function(JNIEnv *env, jobject method) FromReflectedMethod;
    jfieldID function(JNIEnv *env, jobject field) FromReflectedField;

    jobject function(JNIEnv *env, jclass cls, jmethodID methodID, jboolean isStatic) ToReflectedMethod;

    jclass function(JNIEnv *env, jclass sub) GetSuperclass;
    jboolean function(JNIEnv *env, jclass sub, jclass sup) IsAssignableFrom;

    jobject function(JNIEnv *env, jclass cls, jfieldID fieldID, jboolean isStatic) ToReflectedField;

    jint function(JNIEnv *env, jthrowable obj) Throw;
    jint function(JNIEnv *env, jclass clazz, const(char)* msg) ThrowNew;
    jthrowable function(JNIEnv *env) ExceptionOccurred;
    void function(JNIEnv *env) ExceptionDescribe;
    void function(JNIEnv *env) ExceptionClear;
    void function(JNIEnv *env, const(char)* msg) FatalError;

    jint function(JNIEnv *env, jint capacity) PushLocalFrame;
    jobject function(JNIEnv *env, jobject result) PopLocalFrame;

    jobject function(JNIEnv *env, jobject lobj) NewGlobalRef;
    void function(JNIEnv *env, jobject gref) DeleteGlobalRef;
    void function(JNIEnv *env, jobject obj) DeleteLocalRef;
    jboolean function(JNIEnv *env, jobject obj1, jobject obj2) IsSameObject;
    jobject function(JNIEnv *env, jobject _ref) NewLocalRef;
    jint function(JNIEnv *env, jint capacity) EnsureLocalCapacity;

    jobject function(JNIEnv *env, jclass clazz) AllocObject;
    jobject function(JNIEnv *env, jclass clazz, jmethodID methodID, ...) NewObject;
    jobject function(JNIEnv *env, jclass clazz, jmethodID methodID, va_list args) NewObjectV;
    jobject function(JNIEnv *env, jclass clazz, jmethodID methodID, const jvalue *args) NewObjectA;

    jclass function(JNIEnv *env, jobject obj) GetObjectClass;
    jboolean function(JNIEnv *env, jobject obj, jclass clazz) IsInstanceOf;

    jmethodID function(JNIEnv *env, jclass clazz, const(char)* name, const(char)* sig) GetMethodID;

    jobject function(JNIEnv *env, jobject obj, jmethodID methodID, ...) CallObjectMethod;
    jobject function(JNIEnv *env, jobject obj, jmethodID methodID, va_list args) CallObjectMethodV;
    jobject function(JNIEnv *env, jobject obj, jmethodID methodID, const jvalue * args) CallObjectMethodA;

    jboolean function(JNIEnv *env, jobject obj, jmethodID methodID, ...) CallBooleanMethod;
    jboolean function(JNIEnv *env, jobject obj, jmethodID methodID, va_list args) CallBooleanMethodV;
    jboolean function(JNIEnv *env, jobject obj, jmethodID methodID, const jvalue * args) CallBooleanMethodA;

    jbyte function(JNIEnv *env, jobject obj, jmethodID methodID, ...) CallByteMethod;
    jbyte function(JNIEnv *env, jobject obj, jmethodID methodID, va_list args) CallByteMethodV;
    jbyte function(JNIEnv *env, jobject obj, jmethodID methodID, const jvalue *args) CallByteMethodA;

    jchar function(JNIEnv *env, jobject obj, jmethodID methodID, ...) CallCharMethod;
    jchar function(JNIEnv *env, jobject obj, jmethodID methodID, va_list args) CallCharMethodV;
    jchar function(JNIEnv *env, jobject obj, jmethodID methodID, const jvalue *args) CallCharMethodA;

    jshort function(JNIEnv *env, jobject obj, jmethodID methodID, ...) CallShortMethod;
    jshort function(JNIEnv *env, jobject obj, jmethodID methodID, va_list args) CallShortMethodV;
    jshort function(JNIEnv *env, jobject obj, jmethodID methodID, const jvalue *args) CallShortMethodA;

    jint function(JNIEnv *env, jobject obj, jmethodID methodID, ...) CallIntMethod;
    jint function(JNIEnv *env, jobject obj, jmethodID methodID, va_list args) CallIntMethodV;
    jint function(JNIEnv *env, jobject obj, jmethodID methodID, const jvalue *args) CallIntMethodA;

    jlong function(JNIEnv *env, jobject obj, jmethodID methodID, ...) CallLongMethod;
    jlong function(JNIEnv *env, jobject obj, jmethodID methodID, va_list args) CallLongMethodV;
    jlong function(JNIEnv *env, jobject obj, jmethodID methodID, const jvalue *args) CallLongMethodA;

    jfloat function(JNIEnv *env, jobject obj, jmethodID methodID, ...) CallFloatMethod;
    jfloat function(JNIEnv *env, jobject obj, jmethodID methodID, va_list args) CallFloatMethodV;
    jfloat function(JNIEnv *env, jobject obj, jmethodID methodID, const jvalue *args) CallFloatMethodA;

    jdouble function(JNIEnv *env, jobject obj, jmethodID methodID, ...) CallDoubleMethod;
    jdouble function(JNIEnv *env, jobject obj, jmethodID methodID, va_list args) CallDoubleMethodV;
    jdouble function(JNIEnv *env, jobject obj, jmethodID methodID, const jvalue *args) CallDoubleMethodA;

    void function(JNIEnv *env, jobject obj, jmethodID methodID, ...) CallVoidMethod;
    void function(JNIEnv *env, jobject obj, jmethodID methodID, va_list args) CallVoidMethodV;
    void function(JNIEnv *env, jobject obj, jmethodID methodID, const jvalue * args) CallVoidMethodA;

    jobject function(JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID, ...) CallNonvirtualObjectMethod;
    jobject function
      (JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       va_list args) CallNonvirtualObjectMethodV;
    jobject function
      (JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       const jvalue * args) CallNonvirtualObjectMethodA;

    jboolean function(JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID, ...) CallNonvirtualBooleanMethod;
    jboolean function
      (JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       va_list args) CallNonvirtualBooleanMethodV;
    jboolean function
      (JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       const jvalue * args) CallNonvirtualBooleanMethodA;

    jbyte function(JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID, ...) CallNonvirtualByteMethod;
    jbyte function
      (JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       va_list args) CallNonvirtualByteMethodV;
    jbyte function
      (JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       const jvalue *args) CallNonvirtualByteMethodA;

    jchar function(JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID, ...) CallNonvirtualCharMethod;
    jchar function
      (JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       va_list args) CallNonvirtualCharMethodV;
    jchar function
      (JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       const jvalue *args) CallNonvirtualCharMethodA;

    jshort function(JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID, ...) CallNonvirtualShortMethod;
    jshort function
      (JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       va_list args) CallNonvirtualShortMethodV;
    jshort function
      (JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       const jvalue *args) CallNonvirtualShortMethodA;

    jint function(JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID, ...) CallNonvirtualIntMethod;
    jint function
      (JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       va_list args) CallNonvirtualIntMethodV;
    jint function
      (JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       const jvalue *args) CallNonvirtualIntMethodA;

    jlong function(JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID, ...) CallNonvirtualLongMethod;
    jlong function
      (JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       va_list args) CallNonvirtualLongMethodV;
    jlong function
      (JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       const jvalue *args) CallNonvirtualLongMethodA;

    jfloat function(JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID, ...) CallNonvirtualFloatMethod;
    jfloat function
      (JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       va_list args) CallNonvirtualFloatMethodV;
    jfloat function
      (JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       const jvalue *args) CallNonvirtualFloatMethodA;

    jdouble function(JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID, ...) CallNonvirtualDoubleMethod;
    jdouble function
      (JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       va_list args) CallNonvirtualDoubleMethodV;
    jdouble function
      (JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       const jvalue *args) CallNonvirtualDoubleMethodA;

    void function(JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID, ...) CallNonvirtualVoidMethod;
    void
      function(JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       va_list args) CallNonvirtualVoidMethodV;
    void
      function(JNIEnv *env, jobject obj, jclass clazz, jmethodID methodID,
       const(jvalue)* args) CallNonvirtualVoidMethodA;

    jfieldID function(JNIEnv *env, jclass clazz, const(char)* name, const(char)* sig) GetFieldID;

    jobject function(JNIEnv *env, jobject obj, jfieldID fieldID) GetObjectField;
    jboolean function(JNIEnv *env, jobject obj, jfieldID fieldID) GetBooleanField;
    jbyte function(JNIEnv *env, jobject obj, jfieldID fieldID) GetByteField;
    jchar function(JNIEnv *env, jobject obj, jfieldID fieldID) GetCharField;
    jshort function(JNIEnv *env, jobject obj, jfieldID fieldID) GetShortField;
    jint function(JNIEnv *env, jobject obj, jfieldID fieldID) GetIntField;
    jlong function(JNIEnv *env, jobject obj, jfieldID fieldID) GetLongField;
    jfloat function(JNIEnv *env, jobject obj, jfieldID fieldID) GetFloatField;
    jdouble function(JNIEnv *env, jobject obj, jfieldID fieldID) GetDoubleField;

    void function(JNIEnv *env, jobject obj, jfieldID fieldID, jobject val) SetObjectField;
    void function(JNIEnv *env, jobject obj, jfieldID fieldID, jboolean val) SetBooleanField;
    void function(JNIEnv *env, jobject obj, jfieldID fieldID, jbyte val) SetByteField;
    void function(JNIEnv *env, jobject obj, jfieldID fieldID, jchar val) SetCharField;
    void function(JNIEnv *env, jobject obj, jfieldID fieldID, jshort val) SetShortField;
    void function(JNIEnv *env, jobject obj, jfieldID fieldID, jint val) SetIntField;
    void function(JNIEnv *env, jobject obj, jfieldID fieldID, jlong val) SetLongField;
    void function(JNIEnv *env, jobject obj, jfieldID fieldID, jfloat val) SetFloatField;
    void function(JNIEnv *env, jobject obj, jfieldID fieldID, jdouble val) SetDoubleField;

    jmethodID function(JNIEnv *env, jclass clazz, const(char)* name, const(char)* sig) GetStaticMethodID;

    jobject function(JNIEnv *env, jclass clazz, jmethodID methodID, ...) CallStaticObjectMethod;
    jobject function(JNIEnv *env, jclass clazz, jmethodID methodID, va_list args) CallStaticObjectMethodV;
    jobject function(JNIEnv *env, jclass clazz, jmethodID methodID, const jvalue *args) CallStaticObjectMethodA;

    jboolean function(JNIEnv *env, jclass clazz, jmethodID methodID, ...) CallStaticBooleanMethod;
    jboolean function(JNIEnv *env, jclass clazz, jmethodID methodID, va_list args) CallStaticBooleanMethodV;
    jboolean function(JNIEnv *env, jclass clazz, jmethodID methodID, const jvalue *args) CallStaticBooleanMethodA;

    jbyte function(JNIEnv *env, jclass clazz, jmethodID methodID, ...) CallStaticByteMethod;
    jbyte function(JNIEnv *env, jclass clazz, jmethodID methodID, va_list args) CallStaticByteMethodV;
    jbyte function(JNIEnv *env, jclass clazz, jmethodID methodID, const jvalue *args) CallStaticByteMethodA;

    jchar function(JNIEnv *env, jclass clazz, jmethodID methodID, ...) CallStaticCharMethod;
    jchar function(JNIEnv *env, jclass clazz, jmethodID methodID, va_list args) CallStaticCharMethodV;
    jchar function(JNIEnv *env, jclass clazz, jmethodID methodID, const jvalue *args) CallStaticCharMethodA;

    jshort function(JNIEnv *env, jclass clazz, jmethodID methodID, ...) CallStaticShortMethod;
    jshort function(JNIEnv *env, jclass clazz, jmethodID methodID, va_list args) CallStaticShortMethodV;
    jshort function(JNIEnv *env, jclass clazz, jmethodID methodID, const jvalue *args) CallStaticShortMethodA;

    jint function(JNIEnv *env, jclass clazz, jmethodID methodID, ...) CallStaticIntMethod;
    jint function(JNIEnv *env, jclass clazz, jmethodID methodID, va_list args) CallStaticIntMethodV;
    jint function(JNIEnv *env, jclass clazz, jmethodID methodID, const jvalue *args) CallStaticIntMethodA;

    jlong function(JNIEnv *env, jclass clazz, jmethodID methodID, ...) CallStaticLongMethod;
    jlong function(JNIEnv *env, jclass clazz, jmethodID methodID, va_list args) CallStaticLongMethodV;
    jlong function(JNIEnv *env, jclass clazz, jmethodID methodID, const jvalue *args) CallStaticLongMethodA;

    jfloat function(JNIEnv *env, jclass clazz, jmethodID methodID, ...) CallStaticFloatMethod;
    jfloat function(JNIEnv *env, jclass clazz, jmethodID methodID, va_list args) CallStaticFloatMethodV;
    jfloat function(JNIEnv *env, jclass clazz, jmethodID methodID, const jvalue *args) CallStaticFloatMethodA;

    jdouble function(JNIEnv *env, jclass clazz, jmethodID methodID, ...) CallStaticDoubleMethod;
    jdouble function(JNIEnv *env, jclass clazz, jmethodID methodID, va_list args) CallStaticDoubleMethodV;
    jdouble function(JNIEnv *env, jclass clazz, jmethodID methodID, const jvalue *args) CallStaticDoubleMethodA;

    void function(JNIEnv *env, jclass cls, jmethodID methodID, ...) CallStaticVoidMethod;
    void function(JNIEnv *env, jclass cls, jmethodID methodID, va_list args) CallStaticVoidMethodV;
    void function(JNIEnv *env, jclass cls, jmethodID methodID, const jvalue * args) CallStaticVoidMethodA;

    jfieldID function(JNIEnv *env, jclass clazz, const(char)* name, const(char)* sig) GetStaticFieldID;
    jobject function(JNIEnv *env, jclass clazz, jfieldID fieldID) GetStaticObjectField;
    jboolean function(JNIEnv *env, jclass clazz, jfieldID fieldID) GetStaticBooleanField;
    jbyte function(JNIEnv *env, jclass clazz, jfieldID fieldID) GetStaticByteField;
    jchar function(JNIEnv *env, jclass clazz, jfieldID fieldID) GetStaticCharField;
    jshort function(JNIEnv *env, jclass clazz, jfieldID fieldID) GetStaticShortField;
    jint function(JNIEnv *env, jclass clazz, jfieldID fieldID) GetStaticIntField;
    jlong function(JNIEnv *env, jclass clazz, jfieldID fieldID) GetStaticLongField;
    jfloat function(JNIEnv *env, jclass clazz, jfieldID fieldID) GetStaticFloatField;
    jdouble function(JNIEnv *env, jclass clazz, jfieldID fieldID) GetStaticDoubleField;

    void function(JNIEnv *env, jclass clazz, jfieldID fieldID, jobject value) SetStaticObjectField;
    void function(JNIEnv *env, jclass clazz, jfieldID fieldID, jboolean value) SetStaticBooleanField;
    void function(JNIEnv *env, jclass clazz, jfieldID fieldID, jbyte value) SetStaticByteField;
    void function(JNIEnv *env, jclass clazz, jfieldID fieldID, jchar value) SetStaticCharField;
    void function(JNIEnv *env, jclass clazz, jfieldID fieldID, jshort value) SetStaticShortField;
    void function(JNIEnv *env, jclass clazz, jfieldID fieldID, jint value) SetStaticIntField;
    void function(JNIEnv *env, jclass clazz, jfieldID fieldID, jlong value) SetStaticLongField;
    void function(JNIEnv *env, jclass clazz, jfieldID fieldID, jfloat value) SetStaticFloatField;
    void function(JNIEnv *env, jclass clazz, jfieldID fieldID, jdouble value) SetStaticDoubleField;

    jstring function(JNIEnv *env, const(jchar)* unicode, jsize len) NewString;
    jsize function(JNIEnv *env, jstring str) GetStringLength;
    const(jchar)* function(JNIEnv *env, jstring str, jboolean *isCopy) GetStringChars;
    void function(JNIEnv *env, jstring str, const(jchar)* chars) ReleaseStringChars;

    jstring function(JNIEnv *env, const(char)* utf) NewStringUTF;
    jsize function(JNIEnv *env, jstring str) GetStringUTFLength;
    const(char)* function(JNIEnv *env, jstring str, jboolean *isCopy) GetStringUTFChars;
    void function(JNIEnv *env, jstring str, const char* chars) ReleaseStringUTFChars;


    jsize function(JNIEnv *env, jarray array) GetArrayLength;

    jobjectArray function(JNIEnv *env, jsize len, jclass clazz, jobject init) NewObjectArray;
    jobject function(JNIEnv *env, jobjectArray array, jsize index) GetObjectArrayElement;
    void function(JNIEnv *env, jobjectArray array, jsize index, jobject val) SetObjectArrayElement;

    jbooleanArray function(JNIEnv *env, jsize len) NewBooleanArray;
    jbyteArray function(JNIEnv *env, jsize len) NewByteArray;
    jcharArray function(JNIEnv *env, jsize len) NewCharArray;
    jshortArray function(JNIEnv *env, jsize len) NewShortArray;
    jintArray function(JNIEnv *env, jsize len) NewIntArray;
    jlongArray function(JNIEnv *env, jsize len) NewLongArray;
    jfloatArray function(JNIEnv *env, jsize len) NewFloatArray;
    jdoubleArray function(JNIEnv *env, jsize len) NewDoubleArray;

    jboolean function(JNIEnv *env, jbooleanArray array, jboolean *isCopy) GetBooleanArrayElements;
    jbyte function(JNIEnv *env, jbyteArray array, jboolean *isCopy) GetByteArrayElements;
    jchar function(JNIEnv *env, jcharArray array, jboolean *isCopy) GetCharArrayElements;
    jshort function(JNIEnv *env, jshortArray array, jboolean *isCopy) GetShortArrayElements;
    jint function(JNIEnv *env, jintArray array, jboolean *isCopy) GetIntArrayElements;
    jlong function(JNIEnv *env, jlongArray array, jboolean *isCopy) GetLongArrayElements;
    jfloat function(JNIEnv *env, jfloatArray array, jboolean *isCopy) GetFloatArrayElements;
    jdouble function(JNIEnv *env, jdoubleArray array, jboolean *isCopy) GetDoubleArrayElements;

    void function(JNIEnv *env, jbooleanArray array, jboolean *elems, jint mode) ReleaseBooleanArrayElements;
    void function(JNIEnv *env, jbyteArray array, jbyte *elems, jint mode) ReleaseByteArrayElements;
    void function(JNIEnv *env, jcharArray array, jchar *elems, jint mode) ReleaseCharArrayElements;
    void function(JNIEnv *env, jshortArray array, jshort *elems, jint mode) ReleaseShortArrayElements;
    void function(JNIEnv *env, jintArray array, jint *elems, jint mode) ReleaseIntArrayElements;
    void function(JNIEnv *env, jlongArray array, jlong *elems, jint mode) ReleaseLongArrayElements;
    void function(JNIEnv *env, jfloatArray array, jfloat *elems, jint mode) ReleaseFloatArrayElements;
    void function(JNIEnv *env, jdoubleArray array, jdouble *elems, jint mode) ReleaseDoubleArrayElements;

    void function(JNIEnv *env, jbooleanArray array, jsize start, jsize l, jboolean *buf) GetBooleanArrayRegion;
    void function(JNIEnv *env, jbyteArray array, jsize start, jsize len, jbyte *buf) GetByteArrayRegion;
    void function(JNIEnv *env, jcharArray array, jsize start, jsize len, jchar *buf) GetCharArrayRegion;
    void function(JNIEnv *env, jshortArray array, jsize start, jsize len, jshort *buf) GetShortArrayRegion;
    void function(JNIEnv *env, jintArray array, jsize start, jsize len, jint *buf) GetIntArrayRegion;
    void function(JNIEnv *env, jlongArray array, jsize start, jsize len, jlong *buf) GetLongArrayRegion;
    void function(JNIEnv *env, jfloatArray array, jsize start, jsize len, jfloat *buf) GetFloatArrayRegion;
    void function(JNIEnv *env, jdoubleArray array, jsize start, jsize len, jdouble *buf) GetDoubleArrayRegion;

    void function(JNIEnv *env, jbooleanArray array, jsize start, jsize l, const jboolean *buf) SetBooleanArrayRegion;
    void function(JNIEnv *env, jbyteArray array, jsize start, jsize len, const jbyte *buf) SetByteArrayRegion;
    void function(JNIEnv *env, jcharArray array, jsize start, jsize len, const(jchar)* buf) SetCharArrayRegion;
    void function(JNIEnv *env, jshortArray array, jsize start, jsize len, const jshort *buf) SetShortArrayRegion;
    void function(JNIEnv *env, jintArray array, jsize start, jsize len, const jint *buf) SetIntArrayRegion;
    void function(JNIEnv *env, jlongArray array, jsize start, jsize len, const jlong *buf) SetLongArrayRegion;
    void function(JNIEnv *env, jfloatArray array, jsize start, jsize len, const jfloat *buf) SetFloatArrayRegion;
    void function(JNIEnv *env, jdoubleArray array, jsize start, jsize len, const jdouble *buf) SetDoubleArrayRegion;

    jint function(JNIEnv* env, jclass clazz, JNINativeMethod* methods, jint nMethods) RegisterNatives;
    jint function(JNIEnv *env, jclass clazz) UnregisterNatives;

    jint function(JNIEnv *env, jobject obj) MonitorEnter;
    jint function(JNIEnv *env, jobject obj) MonitorExit;

    jint function(JNIEnv *env, JavaVM **vm) GetJavaVM;

    void function(JNIEnv *env, jstring str, jsize start, jsize len, jchar *buf) GetStringRegion;
    void function(JNIEnv *env, jstring str, jsize start, jsize len, char *buf) GetStringUTFRegion;

    void function(JNIEnv *env, jarray array, jboolean *isCopy) GetPrimitiveArrayCritical;
    void function(JNIEnv *env, jarray array, void *carray, jint mode) ReleasePrimitiveArrayCritical;

    const jchar function(JNIEnv *env, jstring _string, jboolean *isCopy) GetStringCritical;
    void function(JNIEnv *env, jstring _string, const(jchar)* cstring) ReleaseStringCritical;

    jweak function(JNIEnv *env, jobject obj) NewWeakGlobalRef;
    void function(JNIEnv *env, jweak _ref) DeleteWeakGlobalRef;

    jboolean function(JNIEnv *env) ExceptionCheck;

    jobject function(JNIEnv* env, void* address, jlong capacity) NewDirectByteBuffer;
    void* function(JNIEnv* env, jobject buf) GetDirectBufferAddress;
    jlong function(JNIEnv* env, jobject buf) GetDirectBufferCapacity;

    jobjectRefType function(JNIEnv* env, jobject obj) GetObjectRefType;
}

struct JNIEnv_ {
    JNINativeInterface_* functions;
}

struct JavaVMOption {
    char *optionString;
    void *extraInfo;
}

struct JavaVMInitArgs {
    jint _version;

    jint nOptions;
    JavaVMOption *options;
    jboolean ignoreUnrecognized;
}

struct JavaVMAttachArgs {
    jint _version;

    char *name;
    jobject group;
}

struct JNIInvokeInterface_ {
    void *reserved0;
    void *reserved1;
    void *reserved2;

    jint function(JavaVM *vm) DestroyJavaVM;

    jint function(JavaVM *vm, void **penv, void *args) AttachCurrentThread;

    jint function(JavaVM *vm) DetachCurrentThread;

    jint function(JavaVM *vm, void **penv, jint _version) GetEnv;

    jint function(JavaVM *vm, void **penv, void *args) AttachCurrentThreadAsDaemon;
}

struct JavaVM_ {
    JNIInvokeInterface_* functions;
}

jint 
JNI_GetDefaultJavaVMInitArgs(void *args);

jint 
JNI_CreateJavaVM(JavaVM **pvm, void **penv, void *args);

jint 
JNI_GetCreatedJavaVMs(JavaVM **, jsize, jsize *);

jint JNI_OnLoad(JavaVM *vm, void *reserved);

void JNI_OnUnload(JavaVM *vm, void *reserved);

enum JNI_VERSION_1_1 = 0x00010001;
enum JNI_VERSION_1_2 = 0x00010002;
enum JNI_VERSION_1_4 = 0x00010004;
enum JNI_VERSION_1_6 = 0x00010006;
