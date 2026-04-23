/*
 * plist.c — Ruby C extension for reading/writing macOS property lists.
 *
 * Provides the OSX::PropertyList module with load/dump methods that
 * bridge between Ruby objects and CoreFoundation property list types.
 *
 * Reconstructed from the original ppc/i386/x86_64 binary's symbol table
 * and the CoreFoundation CFPropertyList API.
 */

#include <ruby.h>
#include <CoreFoundation/CoreFoundation.h>

static VALUE mOSX;
static VALUE mPropertyList;
static VALUE ePlistError;

/* Forward declarations */
static VALUE convertPropertyListRef(CFPropertyListRef plist);
static CFPropertyListRef obj_to_plist(VALUE obj);

/* --- CFPropertyList → Ruby --- */

static VALUE convertStringRef(CFStringRef str)
{
    CFIndex len = CFStringGetLength(str);
    CFIndex maxSize = CFStringGetMaximumSizeForEncoding(len, kCFStringEncodingUTF8) + 1;
    char *buf = ruby_xmalloc(maxSize);
    if (!CFStringGetCString(str, buf, maxSize, kCFStringEncodingUTF8)) {
        free(buf);
        rb_raise(rb_eRuntimeError, "Failed to convert CFString to UTF-8");
    }
    VALUE result = rb_str_new2(buf);
    free(buf);
    rb_funcall(result, rb_intern("force_encoding"), 1, rb_str_new2("UTF-8"));
    return result;
}

static VALUE convertNumberRef(CFNumberRef num)
{
    if (CFNumberIsFloatType(num)) {
        double val;
        CFNumberGetValue(num, kCFNumberDoubleType, &val);
        return rb_float_new(val);
    } else {
        long long val;
        CFNumberGetValue(num, kCFNumberLongLongType, &val);
        return rb_ll2inum(val);
    }
}

static VALUE convertBooleanRef(CFBooleanRef b)
{
    return CFBooleanGetValue(b) ? Qtrue : Qfalse;
}

static VALUE convertDateRef(CFDateRef date)
{
    /* CFAbsoluteTime is seconds since 2001-01-01 00:00:00 UTC */
    CFAbsoluteTime at = CFDateGetAbsoluteTime(date);
    /* Ruby Time uses Unix epoch (1970). Difference is 978307200 seconds. */
    double unixTime = at + 978307200.0;
    return rb_funcall(rb_cTime, rb_intern("at"), 1, rb_float_new(unixTime));
}

static VALUE convertDataRef(CFDataRef data)
{
    const UInt8 *bytes = CFDataGetBytePtr(data);
    CFIndex len = CFDataGetLength(data);
    VALUE str = rb_str_new((const char *)bytes, len);
    /* Mark as ASCII-8BIT (binary) */
    rb_funcall(str, rb_intern("force_encoding"), 1, rb_str_new2("ASCII-8BIT"));
    return str;
}

static VALUE convertArrayRef(CFArrayRef array)
{
    VALUE ary = rb_ary_new();
    CFIndex count = CFArrayGetCount(array);
    for (CFIndex i = 0; i < count; i++) {
        rb_ary_push(ary, convertPropertyListRef(CFArrayGetValueAtIndex(array, i)));
    }
    return ary;
}

static void dictionaryConverter(const void *key, const void *val, void *context)
{
    VALUE hash = (VALUE)context;
    rb_hash_aset(hash, convertPropertyListRef((CFPropertyListRef)key),
                       convertPropertyListRef((CFPropertyListRef)val));
}

static VALUE convertDictionaryRef(CFDictionaryRef dict)
{
    VALUE hash = rb_hash_new();
    CFDictionaryApplyFunction(dict, dictionaryConverter, (void *)hash);
    return hash;
}

static VALUE convertPropertyListRef(CFPropertyListRef plist)
{
    if (plist == NULL) return Qnil;

    CFTypeID typeID = CFGetTypeID(plist);

    if (typeID == CFStringGetTypeID())
        return convertStringRef((CFStringRef)plist);
    else if (typeID == CFNumberGetTypeID())
        return convertNumberRef((CFNumberRef)plist);
    else if (typeID == CFBooleanGetTypeID())
        return convertBooleanRef((CFBooleanRef)plist);
    else if (typeID == CFDateGetTypeID())
        return convertDateRef((CFDateRef)plist);
    else if (typeID == CFDataGetTypeID())
        return convertDataRef((CFDataRef)plist);
    else if (typeID == CFArrayGetTypeID())
        return convertArrayRef((CFArrayRef)plist);
    else if (typeID == CFDictionaryGetTypeID())
        return convertDictionaryRef((CFDictionaryRef)plist);
    else
        return Qnil;
}

/* --- Ruby → CFPropertyList --- */

static CFStringRef convertString(VALUE str)
{
    StringValue(str);
    return CFStringCreateWithBytes(kCFAllocatorDefault,
        (const UInt8 *)RSTRING_PTR(str), RSTRING_LEN(str),
        kCFStringEncodingUTF8, false);
}

static CFNumberRef convertNumber(VALUE num)
{
    if (rb_obj_is_kind_of(num, rb_cFloat) || TYPE(num) == T_FLOAT) {
        double val = rb_num2dbl(num);
        return CFNumberCreate(kCFAllocatorDefault, kCFNumberDoubleType, &val);
    } else {
        long long val = rb_num2ll(num);
        return CFNumberCreate(kCFAllocatorDefault, kCFNumberLongLongType, &val);
    }
}

static CFDateRef convertTime(VALUE time)
{
    VALUE floatTime = rb_funcall(time, rb_intern("to_f"), 0);
    double unixTime = rb_num2dbl(floatTime);
    CFAbsoluteTime at = unixTime - 978307200.0;
    return CFDateCreate(kCFAllocatorDefault, at);
}

static CFArrayRef convertArray(VALUE ary)
{
    CFMutableArrayRef cfary = CFArrayCreateMutable(kCFAllocatorDefault, 0,
                                                    &kCFTypeArrayCallBacks);
    long len = RARRAY_LEN(ary);
    for (long i = 0; i < len; i++) {
        CFPropertyListRef item = obj_to_plist(rb_ary_entry(ary, i));
        if (item) {
            CFArrayAppendValue(cfary, item);
            CFRelease(item);
        }
    }
    return cfary;
}

static void iterateHash(VALUE key, VALUE val, VALUE context)
{
    CFMutableDictionaryRef dict = (CFMutableDictionaryRef)context;
    CFPropertyListRef cfkey = obj_to_plist(key);
    CFPropertyListRef cfval = obj_to_plist(val);
    if (cfkey && cfval) {
        CFDictionaryAddValue(dict, cfkey, cfval);
    }
    if (cfkey) CFRelease(cfkey);
    if (cfval) CFRelease(cfval);
}

static int iterateHashCallback(VALUE key, VALUE val, VALUE context)
{
    iterateHash(key, val, context);
    return ST_CONTINUE;
}

static CFDictionaryRef convertHash(VALUE hash)
{
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    rb_hash_foreach(hash, iterateHashCallback, (VALUE)dict);
    return dict;
}

static CFPropertyListRef obj_to_plist(VALUE obj)
{
    switch (TYPE(obj)) {
        case T_STRING:
            return convertString(obj);
        case T_FIXNUM:
        case T_BIGNUM:
        case T_FLOAT:
            return convertNumber(obj);
        case T_ARRAY:
            return (CFPropertyListRef)convertArray(obj);
        case T_HASH:
            return (CFPropertyListRef)convertHash(obj);
        case T_TRUE:
            return CFRetain(kCFBooleanTrue);
        case T_FALSE:
            return CFRetain(kCFBooleanFalse);
        default:
            if (rb_obj_is_kind_of(obj, rb_cTime)) {
                return convertTime(obj);
            }
            /* Convert to string as fallback */
            return convertString(rb_funcall(obj, rb_intern("to_s"), 0));
    }
}

/* --- Module methods --- */

/*
 * OSX::PropertyList.load(string_or_io)
 *
 * Parse a property list (binary, XML, or OpenStep format) and return
 * the corresponding Ruby object.
 */
static VALUE plist_load(int argc, VALUE *argv, VALUE self)
{
    VALUE data;
    rb_scan_args(argc, argv, "1", &data);

    /* If it responds to :read, call it to get the string */
    if (rb_respond_to(data, rb_intern("read"))) {
        data = rb_funcall(data, rb_intern("read"), 0);
    }

    StringValue(data);

    CFDataRef cfdata = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault,
        (const UInt8 *)RSTRING_PTR(data), RSTRING_LEN(data), kCFAllocatorNull);

    if (!cfdata) {
        rb_raise(ePlistError, "Failed to create CFData from input");
    }

    CFReadStreamRef stream = CFReadStreamCreateWithBytesNoCopy(kCFAllocatorDefault,
        (const UInt8 *)RSTRING_PTR(data), RSTRING_LEN(data), kCFAllocatorNull);

    if (!stream) {
        CFRelease(cfdata);
        rb_raise(ePlistError, "Failed to create read stream");
    }

    CFReadStreamOpen(stream);

    CFStringRef errorString = NULL;
    CFPropertyListRef plist = CFPropertyListCreateFromStream(kCFAllocatorDefault,
        stream, 0, kCFPropertyListImmutable, NULL, &errorString);

    CFReadStreamClose(stream);
    CFRelease(stream);
    CFRelease(cfdata);

    if (!plist) {
        if (errorString) {
            char buf[256];
            CFStringGetCString(errorString, buf, sizeof(buf), kCFStringEncodingUTF8);
            CFRelease(errorString);
            rb_raise(ePlistError, "Property list parsing failed: %s", buf);
        }
        rb_raise(ePlistError, "Property list parsing failed");
    }

    if (errorString) CFRelease(errorString);

    VALUE result = convertPropertyListRef(plist);
    CFRelease(plist);
    return result;
}

/*
 * OSX::PropertyList.dump(object, format = :xml1)
 *
 * Serialize a Ruby object as a property list string.
 * Supported formats: :xml1, :binary1, :open_step
 */
static VALUE plist_dump(int argc, VALUE *argv, VALUE self)
{
    VALUE obj, fmt;
    rb_scan_args(argc, argv, "11", &obj, &fmt);

    CFPropertyListFormat format = kCFPropertyListXMLFormat_v1_0;
    if (fmt != Qnil) {
        ID fmt_id = rb_to_id(fmt);
        if (fmt_id == rb_intern("binary1"))
            format = kCFPropertyListBinaryFormat_v1_0;
        else if (fmt_id == rb_intern("open_step"))
            format = kCFPropertyListOpenStepFormat;
    }

    CFPropertyListRef plist = obj_to_plist(obj);
    if (!plist) {
        rb_raise(ePlistError, "Failed to convert object to property list");
    }

    CFWriteStreamRef stream = CFWriteStreamCreateWithAllocatedBuffers(
        kCFAllocatorDefault, kCFAllocatorDefault);
    CFWriteStreamOpen(stream);

    CFStringRef errorString = NULL;
    CFPropertyListWriteToStream(plist, stream, format, &errorString);

    CFRelease(plist);

    if (errorString) {
        CFWriteStreamClose(stream);
        CFRelease(stream);
        char buf[256];
        CFStringGetCString(errorString, buf, sizeof(buf), kCFStringEncodingUTF8);
        CFRelease(errorString);
        rb_raise(ePlistError, "Property list serialization failed: %s", buf);
    }

    CFDataRef data = CFWriteStreamCopyProperty(stream, kCFStreamPropertyDataWritten);
    CFWriteStreamClose(stream);
    CFRelease(stream);

    if (!data) {
        rb_raise(ePlistError, "Failed to get serialized data");
    }

    VALUE result = rb_str_new((const char *)CFDataGetBytePtr(data), CFDataGetLength(data));
    CFRelease(data);
    return result;
}

/* Blob support (used by codecompletion) */
static VALUE str_setBlob(VALUE self, VALUE blob)
{
    rb_ivar_set(self, rb_intern("@blob"), blob);
    return blob;
}

static VALUE str_blob(VALUE self)
{
    return rb_attr_get(self, rb_intern("@blob"));
}

void Init_plist(void)
{
    mOSX = rb_define_module("OSX");
    mPropertyList = rb_define_module_under(mOSX, "PropertyList");
    ePlistError = rb_define_class_under(mOSX, "PropertyListError", rb_eStandardError);

    rb_define_module_function(mPropertyList, "load", plist_load, -1);
    rb_define_module_function(mPropertyList, "dump", plist_dump, -1);

    /* Blob support on String */
    rb_define_method(rb_cString, "blob=", str_setBlob, 1);
    rb_define_method(rb_cString, "blob", str_blob, 0);

    /* Format constants */
    rb_define_const(mPropertyList, "XML1", ID2SYM(rb_intern("xml1")));
    rb_define_const(mPropertyList, "BINARY1", ID2SYM(rb_intern("binary1")));
    rb_define_const(mPropertyList, "OPEN_STEP", ID2SYM(rb_intern("open_step")));
}
