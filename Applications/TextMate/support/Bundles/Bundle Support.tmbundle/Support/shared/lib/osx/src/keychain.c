/*
 * keychain.c — Ruby C extension for macOS Keychain access.
 *
 * Provides the OSX::Keychain module with methods to find, set, and
 * destroy internet passwords using the Security framework.
 *
 * Reconstructed from the original binary's symbol table and the
 * Security framework SecKeychain API.
 */

#include <ruby.h>
#include <Security/Security.h>

static VALUE mOSX;
static VALUE mKeychain;
static VALUE eKeychainError;

static VALUE getStatusString(OSStatus status)
{
    CFStringRef msg = SecCopyErrorMessageString(status, NULL);
    if (msg) {
        char buf[256];
        CFStringGetCString(msg, buf, sizeof(buf), kCFStringEncodingUTF8);
        CFRelease(msg);
        return rb_str_new2(buf);
    }
    return rb_sprintf("OSStatus %d", (int)status);
}

/*
 * OSX::Keychain.internet_password_for(opts)
 *
 * Find an internet password in the default keychain.
 *
 * Options:
 *   :account  — account name
 *   :server   — server hostname
 *   :protocol — protocol (e.g. "http", as FourCharCode integer)
 *
 * Returns the password string, or nil if not found.
 */
static VALUE internet_password_for(int argc, VALUE *argv, VALUE self)
{
    VALUE opts;
    rb_scan_args(argc, argv, "1", &opts);
    Check_Type(opts, T_HASH);

    VALUE v_account  = rb_hash_aref(opts, ID2SYM(rb_intern("account")));
    VALUE v_server   = rb_hash_aref(opts, ID2SYM(rb_intern("server")));
    VALUE v_protocol = rb_hash_aref(opts, ID2SYM(rb_intern("protocol")));

    const char *account = NIL_P(v_account) ? NULL : StringValuePtr(v_account);
    UInt32 accountLen = account ? (UInt32)strlen(account) : 0;

    const char *server = NIL_P(v_server) ? NULL : StringValuePtr(v_server);
    UInt32 serverLen = server ? (UInt32)strlen(server) : 0;

    SecProtocolType protocol = 0;
    if (!NIL_P(v_protocol)) {
        if (TYPE(v_protocol) == T_FIXNUM || TYPE(v_protocol) == T_BIGNUM) {
            protocol = (SecProtocolType)NUM2LONG(v_protocol);
        } else {
            const char *proto_str = StringValuePtr(v_protocol);
            if (strlen(proto_str) == 4) {
                protocol = (SecProtocolType)((proto_str[0] << 24) | (proto_str[1] << 16) |
                                             (proto_str[2] << 8) | proto_str[3]);
            }
        }
    }

    UInt32 passwordLen = 0;
    void *passwordData = NULL;
    SecKeychainItemRef itemRef = NULL;

    OSStatus status = SecKeychainFindInternetPassword(
        NULL,                               /* default keychain */
        serverLen, server,                  /* server */
        0, NULL,                            /* security domain */
        accountLen, account,                /* account */
        0, NULL,                            /* path */
        0,                                  /* port */
        protocol,                           /* protocol */
        kSecAuthenticationTypeDefault,      /* auth type */
        &passwordLen, &passwordData,        /* password out */
        &itemRef                            /* item ref out */
    );

    if (status == errSecItemNotFound) {
        return Qnil;
    }

    if (status != errSecSuccess) {
        rb_raise(eKeychainError, "SecKeychainFindInternetPassword failed: %s",
                 RSTRING_PTR(getStatusString(status)));
    }

    VALUE result = rb_str_new((const char *)passwordData, passwordLen);
    SecKeychainItemFreeContent(NULL, passwordData);
    if (itemRef) CFRelease(itemRef);

    rb_funcall(result, rb_intern("force_encoding"), 1, rb_str_new2("UTF-8"));
    return result;
}

/*
 * OSX::Keychain.set_internet_password_for(opts)
 *
 * Set (create or update) an internet password in the default keychain.
 *
 * Options:
 *   :account  — account name
 *   :server   — server hostname
 *   :password — the password to store
 *   :protocol — protocol (e.g. "http", as FourCharCode integer)
 */
static VALUE set_internet_password_for(int argc, VALUE *argv, VALUE self)
{
    VALUE opts;
    rb_scan_args(argc, argv, "1", &opts);
    Check_Type(opts, T_HASH);

    VALUE v_account  = rb_hash_aref(opts, ID2SYM(rb_intern("account")));
    VALUE v_server   = rb_hash_aref(opts, ID2SYM(rb_intern("server")));
    VALUE v_password = rb_hash_aref(opts, ID2SYM(rb_intern("password")));
    VALUE v_protocol = rb_hash_aref(opts, ID2SYM(rb_intern("protocol")));

    if (NIL_P(v_password)) {
        rb_raise(rb_eArgError, ":password is required");
    }

    const char *account  = NIL_P(v_account) ? NULL : StringValuePtr(v_account);
    UInt32 accountLen = account ? (UInt32)strlen(account) : 0;

    const char *server   = NIL_P(v_server) ? NULL : StringValuePtr(v_server);
    UInt32 serverLen = server ? (UInt32)strlen(server) : 0;

    const char *password = StringValuePtr(v_password);
    UInt32 passwordLen = (UInt32)strlen(password);

    SecProtocolType protocol = 0;
    if (!NIL_P(v_protocol)) {
        if (TYPE(v_protocol) == T_FIXNUM || TYPE(v_protocol) == T_BIGNUM) {
            protocol = (SecProtocolType)NUM2LONG(v_protocol);
        } else {
            const char *proto_str = StringValuePtr(v_protocol);
            if (strlen(proto_str) == 4) {
                protocol = (SecProtocolType)((proto_str[0] << 24) | (proto_str[1] << 16) |
                                             (proto_str[2] << 8) | proto_str[3]);
            }
        }
    }

    /* Try to find existing entry first */
    SecKeychainItemRef itemRef = NULL;
    OSStatus status = SecKeychainFindInternetPassword(
        NULL, serverLen, server, 0, NULL,
        accountLen, account, 0, NULL, 0,
        protocol, kSecAuthenticationTypeDefault,
        NULL, NULL, &itemRef
    );

    if (status == errSecSuccess && itemRef) {
        /* Update existing */
        status = SecKeychainItemModifyAttributesAndData(
            itemRef, NULL, passwordLen, password);
        CFRelease(itemRef);
    } else {
        /* Create new */
        status = SecKeychainAddInternetPassword(
            NULL,                               /* default keychain */
            serverLen, server,
            0, NULL,                            /* security domain */
            accountLen, account,
            0, NULL,                            /* path */
            0,                                  /* port */
            protocol,
            kSecAuthenticationTypeDefault,
            passwordLen, password,
            NULL                                /* item ref out */
        );
    }

    if (status != errSecSuccess) {
        rb_raise(eKeychainError, "Failed to set internet password: %s",
                 RSTRING_PTR(getStatusString(status)));
    }

    return Qtrue;
}

/*
 * OSX::Keychain.destroy_internet_password_for(opts)
 *
 * Delete an internet password from the default keychain.
 */
static VALUE destroy_internet_password_for(int argc, VALUE *argv, VALUE self)
{
    VALUE opts;
    rb_scan_args(argc, argv, "1", &opts);
    Check_Type(opts, T_HASH);

    VALUE v_account  = rb_hash_aref(opts, ID2SYM(rb_intern("account")));
    VALUE v_server   = rb_hash_aref(opts, ID2SYM(rb_intern("server")));
    VALUE v_protocol = rb_hash_aref(opts, ID2SYM(rb_intern("protocol")));

    const char *account = NIL_P(v_account) ? NULL : StringValuePtr(v_account);
    UInt32 accountLen = account ? (UInt32)strlen(account) : 0;

    const char *server = NIL_P(v_server) ? NULL : StringValuePtr(v_server);
    UInt32 serverLen = server ? (UInt32)strlen(server) : 0;

    SecProtocolType protocol = 0;
    if (!NIL_P(v_protocol)) {
        if (TYPE(v_protocol) == T_FIXNUM || TYPE(v_protocol) == T_BIGNUM) {
            protocol = (SecProtocolType)NUM2LONG(v_protocol);
        } else {
            const char *proto_str = StringValuePtr(v_protocol);
            if (strlen(proto_str) == 4) {
                protocol = (SecProtocolType)((proto_str[0] << 24) | (proto_str[1] << 16) |
                                             (proto_str[2] << 8) | proto_str[3]);
            }
        }
    }

    SecKeychainItemRef itemRef = NULL;
    OSStatus status = SecKeychainFindInternetPassword(
        NULL, serverLen, server, 0, NULL,
        accountLen, account, 0, NULL, 0,
        protocol, kSecAuthenticationTypeDefault,
        NULL, NULL, &itemRef
    );

    if (status == errSecItemNotFound) {
        return Qfalse;
    }

    if (status != errSecSuccess) {
        rb_raise(eKeychainError, "Failed to find internet password: %s",
                 RSTRING_PTR(getStatusString(status)));
    }

    status = SecKeychainItemDelete(itemRef);
    CFRelease(itemRef);

    if (status != errSecSuccess) {
        rb_raise(eKeychainError, "Failed to delete internet password: %s",
                 RSTRING_PTR(getStatusString(status)));
    }

    return Qtrue;
}

void Init_keychain(void)
{
    mOSX = rb_define_module("OSX");
    mKeychain = rb_define_module_under(mOSX, "Keychain");
    eKeychainError = rb_define_class_under(mOSX, "KeychainError", rb_eStandardError);

    rb_define_module_function(mKeychain, "internet_password_for",
                              internet_password_for, -1);
    rb_define_module_function(mKeychain, "set_internet_password_for",
                              set_internet_password_for, -1);
    rb_define_module_function(mKeychain, "destroy_internet_password_for",
                              destroy_internet_password_for, -1);
}
