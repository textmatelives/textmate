#import "OakCommandRefresh.h"
#import <OakCommand/OakCommand.h>
#import <document/OakDocument.h>
#import <document/OakDocumentController.h>
#import <HTMLOutput/HTMLOutput.h>
#import <settings/settings.h>
#import <file/type.h>
#import <ns/ns.h>

@interface OakCommandRefresher ()
{
	OakCommandRefresherOptions _options;
	std::map<std::string, std::string> _variables;
	NSTimer* _idleTimer;
	OakDocument* _loadedDocument; // loaded by us to follow a link; closed when we move on
}
@property (nonatomic, readwrite) OakCommand* command;
@property (nonatomic) OakDocument* document;
@property (nonatomic, weak) NSWindow* window;
@property (nonatomic) BOOL running;
@property (nonatomic) BOOL shouldRun;
- (void)observeDocument:(OakDocument*)document;
- (void)stopObservingDocument:(OakDocument*)document;
- (BOOL)followLinkToPath:(NSString*)path;
- (void)trackDocument:(OakDocument*)document completionHandler:(void(^)())handler;
@end

static NSTimeInterval kDocumentIdleDelay = 0.6;
static NSMutableSet<OakCommandRefresher*>* CommandRefreshers = [NSMutableSet set];

@implementation OakCommandRefresher
+ (OakCommandRefresher*)scheduleRefreshForCommand:(OakCommand*)aCommand document:(OakDocument*)document window:(NSWindow*)window options:(OakCommandRefresherOptions)options variables:(std::map<std::string, std::string> const&)variables
{
	OakCommandRefresher* refresher = [[OakCommandRefresher alloc] initWithCommand:aCommand document:document window:window options:options variables:variables];
	[CommandRefreshers addObject:refresher];
	return refresher;
}

+ (OakCommandRefresher*)findRefresherForCommandUUID:(NSUUID*)anIdentifier document:(OakDocument*)document window:(NSWindow*)window
{
	for(OakCommandRefresher* refresher in CommandRefreshers)
	{
		if([refresher.identifier isEqual:anIdentifier] && (!document || [document isEqual:refresher.document]) && (!window || [window isEqual:refresher.window]))
			return refresher;
	}
	return nil;
}

- (id)initWithCommand:(OakCommand*)aCommand document:(OakDocument*)document window:(NSWindow*)window options:(OakCommandRefresherOptions)options variables:(std::map<std::string, std::string> const&)variables
{
	if((self = [super init]))
	{
		_command   = aCommand;
		_options   = options;
		_document  = document;
		_window    = window;
		_variables = variables;

		_command.updateHTMLViewAtomically = YES;
		_command.htmlOutputView.reusable  = NO;

		__weak OakCommandRefresher* weakSelf = self;
		_command.terminationHandler = ^(OakCommand* command, BOOL normalExit){
			command.updateHTMLViewAtomically = YES; // showDocument: streams once, to get a new page
			if(OakCommandRefresher* refresher = weakSelf)
			{
				refresher.running = NO;
				if(refresher.shouldRun)
				{
					refresher.shouldRun = NO;
					if(normalExit)
						[refresher execute];
				}
			}
		};

		_command.htmlOutputView.localFileHandler = ^BOOL(NSString* path){
			OakCommandRefresher* refresher = weakSelf;
			return refresher ? [refresher followLinkToPath:path] : NO;
		};

		_command.htmlOutputView.documentDidChangeHandler = ^(NSString* path){
			if(OakCommandRefresher* refresher = weakSelf)
				[refresher trackDocument:(path ? [OakDocumentController.sharedInstance documentWithPath:path] : nil) completionHandler:nil];
		};

		[_command.htmlOutputView addObserver:self forKeyPath:@"visible" options:0 context:nullptr];
		[self observeDocument:_document];

		if(_options & OakCommandRefresherDocumentDidSave)
		{
			[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(documentDidSave:) name:OakDocumentDidSaveNotification object:nil];
			[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowWillClose:) name:NSWindowWillCloseNotification object:window];
		}
	}
	return self;
}

- (void)dealloc
{
	_command.htmlOutputView.reusable = YES;
	_command.htmlOutputView.localFileHandler = nil;
	_command.htmlOutputView.documentDidChangeHandler = nil;
	[NSNotificationCenter.defaultCenter removeObserver:self];
	[_loadedDocument close];
	[_command.htmlOutputView removeObserver:self forKeyPath:@"visible"];
}

- (NSUUID*)identifier
{
	return _command.identifier;
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)anObject change:(NSDictionary*)someChanges context:(void*)context
{
	if([keyPath isEqualToString:@"visible"])
		return [self teardown];
	[super observeValueForKeyPath:keyPath ofObject:anObject change:someChanges context:context];
}

- (void)executeForAction:(NSString*)action afterDelay:(BOOL)flag
{
	_variables["TM_REFRESH"] = to_s(action);

	[_idleTimer invalidate];
	if(flag)
			_idleTimer = [NSTimer scheduledTimerWithTimeInterval:kDocumentIdleDelay target:self selector:@selector(idleTimerDidFire:) userInfo:nil repeats:NO];
	else	[self idleTimerDidFire:nil];
}

- (void)idleTimerDidFire:(NSTimer*)aTimer
{
	_idleTimer = nil;
	[self execute];
}

- (void)contentDidChange:(NSNotification*)aNotification
{
	[self executeForAction:@"DocumentChanged" afterDelay:YES];
}

- (void)documentDidSave:(NSNotification*)aNotification
{
	[self executeForAction:@"DocumentSaved" afterDelay:YES];
}

- (void)updateEnvironment:(std::map<std::string, std::string>&)res forCommand:(OakCommand*)aCommand
{
	res << _document.variables;
	res = bundles::scope_variables(res); // Bundle items with a shellVariables setting
	res = variables_for_path(res, to_s(_document.path)); // .tm_properties
}

- (void)documentWillClose:(NSNotification*)aNotification
{
	if(_options & OakCommandRefresherDocumentDidClose)
	{
		_options &= ~OakCommandRefresherDocumentAsInput;
		_command.firstResponder = self;
		[self executeForAction:@"DocumentClosed" afterDelay:NO];
	}

	[_command closeHTMLOutputView];
	[self teardown];
}

- (void)windowWillClose:(NSNotification*)aNotification
{
	[self teardown];
}

- (void)bringHTMLOutputToFront:(id)sender
{
	[[_command.htmlOutputView window] makeKeyAndOrderFront:sender];
}

- (void)teardown
{
	[_idleTimer invalidate];
	_idleTimer = nil;
	[CommandRefreshers removeObject:self];
}

- (void)execute
{
	if(_shouldRun = (_running == YES))
		return;

	NSFileHandle* stdinFH;
	if(_options & OakCommandRefresherDocumentAsInput)
	{
		NSMutableData* data = [NSMutableData data];
		[_document enumerateByteRangesUsingBlock:^(char const* bytes, NSRange byteRange, BOOL* stop){
			[data appendBytes:bytes length:byteRange.length];
		}];

		int stdinRead, stdinWrite;
		std::tie(stdinRead, stdinWrite) = io::create_pipe();

		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			if(write(stdinWrite, data.bytes, data.length) == -1)
				perror("command_info_t: write");
			close(stdinWrite);
		});

		stdinFH = [[NSFileHandle alloc] initWithFileDescriptor:stdinRead closeOnDealloc:YES];
	}
	[_command executeWithInput:stdinFH variables:_variables outputHandler:nil];
}

// ==============================
// = Browsing between documents =
// ==============================

- (void)observeDocument:(OakDocument*)document
{
	if(_options & OakCommandRefresherDocumentDidChange)
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(contentDidChange:) name:OakDocumentContentDidChangeNotification object:document];

	if(_options & (OakCommandRefresherDocumentDidChange|OakCommandRefresherDocumentDidClose))
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(documentWillClose:) name:OakDocumentWillCloseNotification object:document];
}

- (void)stopObservingDocument:(OakDocument*)document
{
	[NSNotificationCenter.defaultCenter removeObserver:self name:OakDocumentContentDidChangeNotification object:document];
	[NSNotificationCenter.defaultCenter removeObserver:self name:OakDocumentWillCloseNotification object:document];
}

- (BOOL)followLinkToPath:(NSString*)path
{
	std::map<std::string, std::string> variables = _variables;
	variables["TM_SCOPE"] = file::type_from_path(to_s(path));
	return [self showDocument:[OakDocumentController.sharedInstance documentWithPath:path] variables:variables];
}

- (BOOL)showDocument:(OakDocument*)document variables:(std::map<std::string, std::string> const&)variables
{
	// The file type is only known once a document has loaded, so fall back to the path for one that has not
	std::string const fileType = document.fileType ? to_s(document.fileType) : file::type_from_path(to_s(document.path));
	if(!(_options & OakCommandRefresherDocumentAsInput) || !command_accepts_document(_command.bundleCommand, fileType))
		return NO;

	_variables = variables;
	_variables.erase("TM_REFRESH");
	_command.firstResponder = self;
	_command.updateHTMLViewAtomically = NO;

	__weak OakCommandRefresher* weakSelf = self;
	[self trackDocument:document completionHandler:^{
		[weakSelf execute];
	}];
	return YES;
}

// Make the given document the one this refresher follows, loading it if no one has, and run the handler once it is ready.
- (void)trackDocument:(OakDocument*)document completionHandler:(void(^)())handler
{
	if(!document)
		return;

	BOOL const changed = document != _document;
	if(changed)
	{
		[self stopObservingDocument:_document];
		[std::exchange(_loadedDocument, nil) close];
		_document = document;
	}

	if(_document.isLoaded)
	{
		if(changed)
			[self observeDocument:_document];
		if(handler)
			handler();
	}
	else
	{
		// Observe only once loaded: filling the buffer posts a content change, which would schedule a second, atomic run
		__weak OakCommandRefresher* weakSelf = self;
		OakDocument* loading = _document;
		[loading loadModalForWindow:nil completionHandler:^(OakDocumentIOResult result, NSString* errorMessage, oak::uuid_t const& filterUUID){
			OakCommandRefresher* refresher = weakSelf;
			if(result != OakDocumentIOResultSuccess || !refresher || refresher.document != loading)
				return [loading close];
			refresher->_loadedDocument = loading;
			[refresher observeDocument:loading];
			if(handler)
				handler();
		}];
	}
}
@end
