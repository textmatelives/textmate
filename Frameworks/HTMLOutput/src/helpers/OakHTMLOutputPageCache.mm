#import "OakHTMLOutputPageCache.h"

@implementation OakHTMLOutputPageCache
{
	NSUInteger _capacity;
	NSMutableArray<NSString*>* _keys; // least recently used first
	NSMutableDictionary<NSString*, NSData*>* _pages;
}

+ (instancetype)sharedCache
{
	static OakHTMLOutputPageCache* cache = [[self alloc] initWithCapacity:32];
	return cache;
}

- (instancetype)initWithCapacity:(NSUInteger)capacity
{
	if(self = [super init])
	{
		_capacity = capacity;
		_keys     = [NSMutableArray new];
		_pages    = [NSMutableDictionary new];
	}
	return self;
}

- (void)setData:(NSData*)data forKey:(NSString*)key
{
	[_keys removeObject:key];
	[_keys addObject:key];
	_pages[key] = data;

	while(_keys.count > _capacity)
	{
		[_pages removeObjectForKey:_keys.firstObject];
		[_keys removeObjectAtIndex:0];
	}
}

- (NSData*)dataForKey:(NSString*)key
{
	NSData* data = _pages[key];
	if(data)
	{
		[_keys removeObject:key];
		[_keys addObject:key];
	}
	return data;
}

- (NSUInteger)count
{
	return _keys.count;
}
@end
