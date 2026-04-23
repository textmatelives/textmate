#import "BundleFetcher.h"
#import "BundleSpec.h"
#import <oak/debug.h>

static NSString* const kErrorDomain = @"BundleFetcher";

static NSString* const kHeaderETag         = @"ETag";
static NSString* const kHeaderIfNoneMatch  = @"If-None-Match";
static NSString* const kHeaderUserAgent    = @"User-Agent";
static NSString* const kHeaderAccept       = @"Accept";
static NSString* const kGitHubV3MediaType  = @"application/vnd.github+json";

@interface BundleFetcher ()
+ (NSString*)userAgentString;
@end

@implementation BundleSHAResolution
{
@public
	NSString* _sha;
	NSString* _etag;
	BOOL      _notModified;
}
- (NSString*)sha  { return _sha; }
- (NSString*)etag { return _etag; }
- (BOOL)notModified { return _notModified; }
@end

// =====================
// = Tarball fetch/extract helper (file-private)
// =====================

@interface BundleArchiveTask : NSObject <NSURLSessionDataDelegate>
{
	BundleSpec* _spec;
	NSURL*      _destURL;
	NSURL*      _stagingURL;
	NSTask*     _tar;
	NSFileHandle* _tarInput;
	dispatch_group_t _tarGroup;
	NSData*     _tarErrorData;
	NSError*    _stagingError;
	void(^_completion)(NSString* installedSHA, NSError* error);
}
@end

@implementation BundleArchiveTask

- (instancetype)initWithSpec:(BundleSpec*)spec destURL:(NSURL*)destURL completion:(void(^)(NSString*, NSError*))completion
{
	if(self = [super init])
	{
		_spec       = spec;
		_destURL    = destURL;
		_completion = completion;
		_tarGroup   = dispatch_group_create();
	}
	return self;
}

- (void)start
{
	NSString* owner = nil;
	NSString* repo  = nil;
	if(![BundleFetcher parseURL:_spec.url owner:&owner repo:&repo])
	{
		[self finishWithSHA:nil error:[self errorWithCode:1 message:[NSString stringWithFormat:@"Cannot parse URL: %@", _spec.url]]];
		return;
	}

	NSString* encodedRef = [_spec.ref stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
	NSString* urlStr = [NSString stringWithFormat:@"https://codeload.github.com/%@/%@/tar.gz/%@", owner, repo, encodedRef];
	NSURL* url = [NSURL URLWithString:urlStr];

	NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60];
	[req setValue:[BundleFetcher userAgentString] forHTTPHeaderField:kHeaderUserAgent];

	NSURLSession* session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration delegate:self delegateQueue:NSOperationQueue.mainQueue];
	[[session dataTaskWithRequest:req] resume];
	[session finishTasksAndInvalidate];
}

- (NSFileHandle*)tarInput
{
	if(_tarInput)
		return _tarInput;

	NSError* error;
	_stagingURL = [NSFileManager.defaultManager URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask appropriateForURL:_destURL create:YES error:&error];
	if(!_stagingURL)
	{
		_stagingError = error;
		return nil;
	}

	NSPipe* inputPipe = [NSPipe pipe];
	NSPipe* errorPipe = [NSPipe pipe];

	_tar = [NSTask new];
	_tar.launchPath = @"/usr/bin/tar";
	_tar.arguments  = @[ @"-zxmkC", _stagingURL.path, @"--strip-components", @"1", @"--disable-copyfile", @"--exclude", @"._*" ];
	_tar.standardInput  = inputPipe;
	_tar.standardError  = errorPipe;
	_tar.standardOutput = [NSFileHandle fileHandleWithNullDevice];

	dispatch_group_async(_tarGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		self->_tarErrorData = [errorPipe.fileHandleForReading readDataToEndOfFile];
		[errorPipe.fileHandleForReading closeFile];
	});

	dispatch_group_t group = _tarGroup;
	dispatch_group_enter(group);
	_tar.terminationHandler = ^(NSTask* t){ dispatch_group_leave(group); };

	if(@available(macos 10.13, *))
	{
		if(![_tar launchAndReturnError:&error])
		{
			_stagingError = error;
			dispatch_group_leave(group); // termination handler will never fire
			[errorPipe.fileHandleForWriting closeFile];
			_tar = nil;
			return nil;
		}
	}
	else
	{
		@try { [_tar launch]; }
		@catch(NSException* e)
		{
			_stagingError = [NSError errorWithDomain:kErrorDomain code:5 userInfo:@{ NSLocalizedDescriptionKey: e.reason ?: @"NSTask launch failed" }];
			dispatch_group_leave(group);
			[errorPipe.fileHandleForWriting closeFile];
			_tar = nil;
			return nil;
		}
	}

	_tarInput = inputPipe.fileHandleForWriting;
	return _tarInput;
}

- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)task didReceiveResponse:(NSURLResponse*)response completionHandler:(void(^)(NSURLSessionResponseDisposition))completionHandler
{
	NSHTTPURLResponse* http = (NSHTTPURLResponse*)response;
	if(http.statusCode / 100 != 2)
	{
		completionHandler(NSURLSessionResponseCancel);
		[self finishWithSHA:nil error:[self errorWithCode:http.statusCode message:[NSString stringWithFormat:@"HTTP %ld from %@", (long)http.statusCode, task.currentRequest.URL]]];
		return;
	}
	completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)task didReceiveData:(NSData*)data
{
	if(NSFileHandle* fh = self.tarInput)
		[fh writeData:data];
	else
		[task cancel];
}

- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(NSError*)networkError
{
	[_tarInput closeFile];
	_tarInput = nil;

	if(networkError)
	{
		[self finishWithSHA:nil error:networkError];
		return;
	}

	if(_stagingError)
	{
		[self finishWithSHA:nil error:_stagingError];
		return;
	}

	dispatch_group_notify(_tarGroup, dispatch_get_main_queue(), ^{
		if(self->_tar.terminationStatus != 0)
		{
			NSString* msg = self->_tarErrorData.length ? [[NSString alloc] initWithData:self->_tarErrorData encoding:NSUTF8StringEncoding] : [NSString stringWithFormat:@"tar exited %d", self->_tar.terminationStatus];
			[self finishWithSHA:nil error:[self errorWithCode:2 message:[msg stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]]];
			return;
		}

		[self validateAndSwap];
	});
}

- (void)validateAndSwap
{
	NSString* infoPath = [_stagingURL.path stringByAppendingPathComponent:@"info.plist"];
	NSDictionary* info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
	NSString* extractedUUID = info[@"uuid"];
	if(!extractedUUID || ![[[NSUUID alloc] initWithUUIDString:extractedUUID] isEqual:_spec.uuid])
	{
		[self finishWithSHA:nil error:[self errorWithCode:3 message:[NSString stringWithFormat:@"info.plist UUID mismatch in %@ (expected %@, got %@)", _spec.name, _spec.uuid.UUIDString, extractedUUID ?: @"(nil)"]]];
		return;
	}

	// Ensure parent of destURL exists.
	NSError* err;
	NSURL* parent = [_destURL URLByDeletingLastPathComponent];
	if(![NSFileManager.defaultManager createDirectoryAtURL:parent withIntermediateDirectories:YES attributes:nil error:&err])
	{
		[self finishWithSHA:nil error:err];
		return;
	}

	// Atomic swap; if destURL does not exist yet, we move instead of replace.
	NSURL* resultURL;
	if([NSFileManager.defaultManager fileExistsAtPath:_destURL.path])
	{
		if(![NSFileManager.defaultManager replaceItemAtURL:_destURL withItemAtURL:_stagingURL backupItemName:nil options:NSFileManagerItemReplacementUsingNewMetadataOnly resultingItemURL:&resultURL error:&err])
		{
			[self finishWithSHA:nil error:err];
			return;
		}
	}
	else
	{
		if(![NSFileManager.defaultManager moveItemAtURL:_stagingURL toURL:_destURL error:&err])
		{
			[self finishWithSHA:nil error:err];
			return;
		}
	}
	_stagingURL = nil; // no longer owned by us

	// Best-effort: the actual SHA isn't returned by codeload. Callers should
	// have resolved it separately (via BundleFetcher resolveSHAForSpec:).
	// If the caller didn't, fall back to echoing the ref — acceptable when
	// ref is already a SHA; misleading for branches, which is why the
	// normal flow is resolve-then-fetch.
	[self finishWithSHA:_spec.ref error:nil];
}

- (void)finishWithSHA:(NSString*)sha error:(NSError*)error
{
	if(_stagingURL)
	{
		NSError* rmErr;
		if(![NSFileManager.defaultManager removeItemAtURL:_stagingURL error:&rmErr])
			os_log_error(OS_LOG_DEFAULT, "Unable to clean staging dir %{public}@: %{public}@", _stagingURL.path, rmErr.localizedDescription);
		_stagingURL = nil;
	}
	void(^cb)(NSString*, NSError*) = _completion;
	_completion = nil;
	if(cb)
		cb(sha, error);
}

- (NSError*)errorWithCode:(NSInteger)code message:(NSString*)message
{
	return [NSError errorWithDomain:kErrorDomain code:code userInfo:@{ NSLocalizedDescriptionKey: message ?: @"Unknown error" }];
}

@end

// =====================
// = BundleFetcher
// =====================

@implementation BundleFetcher

+ (instancetype)sharedInstance
{
	static BundleFetcher* sharedInstance = [self new];
	return sharedInstance;
}

+ (NSString*)userAgentString
{
	static NSString* ua;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSString* name    = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"]    ?: @"TextMate";
		NSString* version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"dev";
		ua = [NSString stringWithFormat:@"%@/%@ (BundleFetcher)", name, version];
	});
	return ua;
}

+ (BOOL)parseURL:(NSString*)url owner:(NSString**)outOwner repo:(NSString**)outRepo
{
	NSURLComponents* c = [NSURLComponents componentsWithString:url ?: @""];
	if(!c || ![c.host.lowercaseString isEqualToString:@"github.com"])
		return NO;

	NSArray<NSString*>* parts = [c.path componentsSeparatedByString:@"/"];
	// Expect ["", "owner", "repo(.git)?"]
	if(parts.count < 3 || parts[1].length == 0 || parts[2].length == 0)
		return NO;

	NSString* owner = parts[1];
	NSString* repo  = parts[2];
	if([repo hasSuffix:@".git"])
		repo = [repo substringToIndex:repo.length - 4];

	if(outOwner) *outOwner = owner;
	if(outRepo)  *outRepo  = repo;
	return YES;
}

- (void)resolveSHAForSpec:(BundleSpec*)spec conditionalEtag:(NSString*)etag completion:(void(^)(BundleSHAResolution*, NSError*))completion
{
	NSString* owner = nil;
	NSString* repo  = nil;
	if(![BundleFetcher parseURL:spec.url owner:&owner repo:&repo])
	{
		completion(nil, [NSError errorWithDomain:kErrorDomain code:1 userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Cannot parse URL: %@", spec.url] }]);
		return;
	}

	NSString* encodedRef = [spec.ref stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
	NSString* urlStr = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/commits/%@", owner, repo, encodedRef];

	NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
	[req setValue:[BundleFetcher userAgentString] forHTTPHeaderField:kHeaderUserAgent];
	[req setValue:kGitHubV3MediaType forHTTPHeaderField:kHeaderAccept];
	if(etag.length)
		[req setValue:etag forHTTPHeaderField:kHeaderIfNoneMatch];

	NSURLSessionDataTask* task = [NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData* data, NSURLResponse* response, NSError* error){
		dispatch_async(dispatch_get_main_queue(), ^{
			if(error)
			{
				completion(nil, error);
				return;
			}

			NSHTTPURLResponse* http = (NSHTTPURLResponse*)response;
			BundleSHAResolution* result = [BundleSHAResolution new];
			result->_etag = http.allHeaderFields[kHeaderETag];

			if(http.statusCode == 304)
			{
				result->_notModified = YES;
				result->_etag = etag; // server omits ETag on 304 sometimes
				completion(result, nil);
				return;
			}

			if(http.statusCode / 100 != 2)
			{
				completion(nil, [NSError errorWithDomain:kErrorDomain code:http.statusCode userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld from GitHub API (%@)", (long)http.statusCode, urlStr] }]);
				return;
			}

			NSDictionary* json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
			NSString* sha = json[@"sha"];
			if(sha.length != 40)
			{
				completion(nil, [NSError errorWithDomain:kErrorDomain code:4 userInfo:@{ NSLocalizedDescriptionKey: @"Missing or malformed sha in GitHub response" }]);
				return;
			}
			result->_sha = sha;
			completion(result, nil);
		});
	}];
	[task resume];
}

- (void)fetchAndInstallSpec:(BundleSpec*)spec intoURL:(NSURL*)destURL completion:(void(^)(NSString*, NSError*))completion
{
	BundleArchiveTask* task = [[BundleArchiveTask alloc] initWithSpec:spec destURL:destURL completion:^(NSString* installedSHA, NSError* error){
		completion(installedSHA, error);
	}];
	[task start];
	// task is retained by its own NSURLSession delegate reference until the
	// session invalidates. Not stored here.
}

@end
