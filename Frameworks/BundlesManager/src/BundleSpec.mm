#import "BundleSpec.h"

static NSString* const kKeyUUID         = @"uuid";
static NSString* const kKeyName         = @"name";
static NSString* const kKeyURL          = @"url";
static NSString* const kKeyRef          = @"ref";
static NSString* const kKeyAutoUpdate   = @"autoUpdate";
static NSString* const kKeyInstalledSHA = @"installedSHA";
static NSString* const kKeyInstalledAt  = @"installedAt";
static NSString* const kKeyETag         = @"etag";

static NSString* const kDefaultRef = @"main";

@implementation BundleSpec

- (instancetype)initWithUUID:(NSUUID*)uuid name:(NSString*)name url:(NSString*)url ref:(NSString*)ref
{
	if(!uuid || !name.length || !url.length)
		return nil;

	if(self = [super init])
	{
		_uuid       = uuid;
		_name       = [name copy];
		_url        = [url copy];
		_ref        = [(ref.length ? ref : kDefaultRef) copy];
		_autoUpdate = YES;
		_origin     = TMBundleOriginUser;
	}
	return self;
}

- (instancetype)initWithPlistRepresentation:(NSDictionary*)plist
{
	NSString* uuidStr = plist[kKeyUUID];
	NSUUID* uuid = uuidStr ? [[NSUUID alloc] initWithUUIDString:uuidStr] : nil;
	if(!uuid)
		return nil;

	if(!(self = [self initWithUUID:uuid name:plist[kKeyName] url:plist[kKeyURL] ref:plist[kKeyRef]]))
		return nil;

	if(NSNumber* n = plist[kKeyAutoUpdate])
		_autoUpdate = n.boolValue;

	_installedSHA = [plist[kKeyInstalledSHA] copy];
	_installedAt  = [plist[kKeyInstalledAt] copy];
	_etag         = [plist[kKeyETag] copy];

	return self;
}

- (NSDictionary*)plistRepresentation
{
	NSMutableDictionary* d = [NSMutableDictionary dictionary];
	d[kKeyUUID]       = _uuid.UUIDString;
	d[kKeyName]       = _name;
	d[kKeyURL]        = _url;
	d[kKeyRef]        = _ref;
	d[kKeyAutoUpdate] = @(_autoUpdate);
	if(_installedSHA) d[kKeyInstalledSHA] = _installedSHA;
	if(_installedAt)  d[kKeyInstalledAt]  = _installedAt;
	if(_etag)         d[kKeyETag]         = _etag;
	return d;
}

- (BOOL)isPinnedToSHA
{
	if(_ref.length != 40)
		return NO;

	NSCharacterSet* hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
	return [[_ref stringByTrimmingCharactersInSet:hex] length] == 0;
}

- (id)copyWithZone:(NSZone*)zone
{
	BundleSpec* copy = [[BundleSpec allocWithZone:zone] initWithUUID:_uuid name:_name url:_url ref:_ref];
	copy.autoUpdate   = _autoUpdate;
	copy.origin       = _origin;
	copy.installedSHA = _installedSHA;
	copy.installedAt  = _installedAt;
	copy.etag         = _etag;
	return copy;
}

- (BOOL)isEqual:(id)other
{
	return [other isKindOfClass:[self class]] && [self.uuid isEqual:[(BundleSpec*)other uuid]];
}

- (NSUInteger)hash
{
	return _uuid.hash;
}

- (NSString*)description
{
	return [NSString stringWithFormat:@"<BundleSpec %@ %@@%@%@>",
		_name, _url, _ref, _installedSHA ? [@" installed=" stringByAppendingString:[_installedSHA substringToIndex:7]] : @""];
}

@end
