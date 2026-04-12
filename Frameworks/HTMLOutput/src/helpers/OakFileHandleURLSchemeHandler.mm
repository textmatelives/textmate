#import "OakFileHandleURLSchemeHandler.h"
#import "OakHTMLOutputRequestMetadata.h"
#import <OakSystem/process.h>

@implementation OakFileHandleURLSchemeHandler
{
	NSMutableDictionary<NSValue*, NSNumber*>* _stoppedTasks;
}

- (instancetype)init
{
	if(self = [super init])
	{
		_stoppedTasks = [NSMutableDictionary new];
	}
	return self;
}

- (void)webView:(WKWebView*)webView startURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask
{
	NSString* urlString = urlSchemeTask.request.URL.absoluteString;
	OakHTMLOutputRequestMetadata* metadata = [OakHTMLOutputRequestMetadata metadataForURLString:urlString];

	if(!metadata || !metadata.fileHandle)
	{
		NSURLResponse* response = [[NSHTTPURLResponse alloc] initWithURL:urlSchemeTask.request.URL
			statusCode:404 HTTPVersion:@"HTTP/1.1" headerFields:nil];
		[urlSchemeTask didReceiveResponse:response];
		[urlSchemeTask didFinish];
		NSLog(@"No command output for '%@'", urlSchemeTask.request.URL);
		return;
	}

	NSURLResponse* response = [[NSURLResponse alloc] initWithURL:urlSchemeTask.request.URL
		MIMEType:@"text/html" expectedContentLength:-1 textEncodingName:@"utf-8"];
	[urlSchemeTask didReceiveResponse:response];

	NSFileHandle* fileHandle = metadata.fileHandle;
	NSValue* taskKey = [NSValue valueWithNonretainedObject:urlSchemeTask];

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		int len;
		char buf[8192];
		__block BOOL keepRunning = YES;
		NSMutableData* __strong carryover = nil;

		@try {
			while(keepRunning && (len = read(fileHandle.fileDescriptor, buf, sizeof(buf))) > 0)
			{
				NSData* rawData = [NSData dataWithBytes:buf length:len];
				NSData* data = RewriteFileURLs(rawData, &carryover);
				dispatch_sync(dispatch_get_main_queue(), ^{
					if(self->_stoppedTasks[taskKey])
					{
						keepRunning = NO;
					}
					else
					{
						if(data.length > 0)
							[urlSchemeTask didReceiveData:data];
					}
				});
			}
		}
		@catch(NSException* e) {
			NSData* data = [[NSString stringWithFormat:@"<p>Exception thrown while reading data: %@.</p>",
				e.reason] dataUsingEncoding:NSUTF8StringEncoding];
			dispatch_sync(dispatch_get_main_queue(), ^{
				if(!self->_stoppedTasks[taskKey])
					[urlSchemeTask didReceiveData:data];
			});
		}

		// Flush any remaining carryover
		if(carryover && carryover.length > 0)
		{
			NSData* remaining = [carryover copy];
			carryover = nil;
			dispatch_sync(dispatch_get_main_queue(), ^{
				if(!self->_stoppedTasks[taskKey])
					[urlSchemeTask didReceiveData:remaining];
			});
		}

		if(len == -1)
			perror("HTMLOutput: read");

		[fileHandle closeFile];
		dispatch_async(dispatch_get_main_queue(), ^{
			if(!self->_stoppedTasks[taskKey])
				[urlSchemeTask didFinish];
			[self->_stoppedTasks removeObjectForKey:taskKey];
			[OakHTMLOutputRequestMetadata removeMetadataForURLString:urlString];
		});
	});
}

- (void)webView:(WKWebView*)webView stopURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask
{
	NSValue* taskKey = [NSValue valueWithNonretainedObject:urlSchemeTask];
	_stoppedTasks[taskKey] = @YES;

	NSString* urlString = urlSchemeTask.request.URL.absoluteString;
	OakHTMLOutputRequestMetadata* metadata = [OakHTMLOutputRequestMetadata metadataForURLString:urlString];
	if(pid_t pid = metadata.processIdentifier.intValue)
		oak::kill_process_group_in_background(pid);
}

static NSData* RewriteFileURLs(NSData* data, NSMutableData* __strong *carryover)
{
	// Prepend any carryover from previous chunk
	NSMutableData* working;
	if(*carryover && (*carryover).length > 0)
	{
		working = [NSMutableData dataWithData:*carryover];
		[working appendData:data];
	}
	else
	{
		working = [NSMutableData dataWithData:data];
	}

	NSData* searchBytes = [@"file://" dataUsingEncoding:NSUTF8StringEncoding];
	NSData* replaceBytes = [@"tm-file://" dataUsingEncoding:NSUTF8StringEncoding];

	NSMutableData* result = [NSMutableData data];
	const uint8_t* bytes = (const uint8_t*)working.bytes;
	NSUInteger length = working.length;
	NSUInteger i = 0;

	while(i < length)
	{
		if(length - i < searchBytes.length)
		{
			// Save as carryover for next chunk
			*carryover = [NSMutableData dataWithBytes:bytes + i length:length - i];
			return result;
		}

		if(memcmp(bytes + i, searchBytes.bytes, searchBytes.length) == 0)
		{
			[result appendData:replaceBytes];
			i += searchBytes.length;
		}
		else
		{
			[result appendBytes:bytes + i length:1];
			i++;
		}
	}

	*carryover = nil;
	return result;
}
@end
