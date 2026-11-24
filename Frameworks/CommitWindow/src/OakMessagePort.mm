#import "OakMessagePort.h"

static NSData* OakMessagePortEncode (NSDictionary* plist)
{
	return plist ? [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil] : nil;
}

static NSDictionary* OakMessagePortDecode (CFDataRef data)
{
	if(!data)
		return @{ };
	id plist = [NSPropertyListSerialization propertyListWithData:(__bridge NSData*)data options:NSPropertyListImmutable format:nil error:nil];
	return [plist isKindOfClass:[NSDictionary class]] ? plist : @{ };
}

@interface OakMessagePortServer ()
@property (nonatomic, copy) OakMessagePortHandler handler;
@end

static CFDataRef OakMessagePortServerCallback (CFMessagePortRef port, SInt32 messageID, CFDataRef data, void* info)
{
	OakMessagePortServer* server = (__bridge OakMessagePortServer*)info;
	NSDictionary* reply = server.handler ? server.handler(OakMessagePortDecode(data)) : nil;
	NSData* replyData = OakMessagePortEncode(reply);
	return replyData ? (CFDataRef)CFBridgingRetain(replyData) : NULL; // the framework releases it
}

@implementation OakMessagePortServer
{
	CFMessagePortRef _port;
	CFRunLoopSourceRef _source;
}

- (instancetype)initWithName:(NSString*)name handler:(OakMessagePortHandler)handler
{
	if(self = [super init])
	{
		_name    = [name copy];
		_handler = handler;

		// Inside one process CFMessagePortCreateLocal hands back an existing port of the same name instead of failing, so check first
		if(CFMessagePortRef taken = CFMessagePortCreateRemote(kCFAllocatorDefault, (__bridge CFStringRef)name))
		{
			CFRelease(taken);
			return nil;
		}

		CFMessagePortContext context = { 0, (__bridge void*)self, NULL, NULL, NULL };
		Boolean shouldFreeInfo = false;
		_port = CFMessagePortCreateLocal(kCFAllocatorDefault, (__bridge CFStringRef)name, &OakMessagePortServerCallback, &context, &shouldFreeInfo);
		if(!_port)
			return nil;

		_source = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, _port, 0);
		CFRunLoopAddSource(CFRunLoopGetCurrent(), _source, kCFRunLoopCommonModes);
	}
	return self;
}

- (void)invalidate
{
	if(_source)
	{
		CFRunLoopSourceInvalidate(_source);
		CFRelease(_source);
		_source = NULL;
	}
	if(_port)
	{
		CFMessagePortInvalidate(_port);
		CFRelease(_port);
		_port = NULL;
	}
}

- (void)dealloc
{
	[self invalidate];
}
@end

NSDictionary* OakMessagePortSendRequest (NSString* name, NSDictionary* request, NSTimeInterval timeout)
{
	CFMessagePortRef remote = CFMessagePortCreateRemote(kCFAllocatorDefault, (__bridge CFStringRef)name);
	if(!remote)
		return nil;

	CFDataRef replyData = NULL;
	SInt32 status = CFMessagePortSendRequest(remote, 0, (__bridge CFDataRef)OakMessagePortEncode(request ?: @{ }), timeout, timeout, kCFRunLoopDefaultMode, &replyData);
	CFRelease(remote);

	if(status != kCFMessagePortSuccess)
	{
		if(replyData)
			CFRelease(replyData);
		return nil;
	}

	NSDictionary* reply = OakMessagePortDecode(replyData);
	if(replyData)
		CFRelease(replyData);
	return reply;
}
