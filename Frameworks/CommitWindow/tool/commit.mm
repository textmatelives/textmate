#include <CommitWindow/CommitWindow.h>
#include <CommitWindow/OakMessagePort.h>
#include <oak/oak.h>

static double const AppVersion = 1.2;

int main (int argc, char* argv[])
{
	if(argc == 2 && (strcmp(argv[1], "-v") == 0 || strcmp(argv[1], "--version") == 0))
	{
		fprintf(stderr, "%1$s %2$.1f (" __DATE__ ")\n", getprogname(), AppVersion);
		return EX_OK;
	}

	@autoreleasepool {
		// The app answers on a port of ours once the user is done with the commit window
		NSString* portName = [NSString stringWithFormat:@"com.macromates.commit-window-client.%d", getpid()];
		__block NSDictionary* result;
		OakMessagePortServer* client = [[OakMessagePortServer alloc] initWithName:portName handler:^NSDictionary*(NSDictionary* options){
			result = options;
			CFRunLoopStop(CFRunLoopGetCurrent());
			return nil;
		}];

		if(!client)
		{
			fprintf(stderr, "%s: failed vending object as ‘%s’\n", getprogname(), portName.UTF8String);
			return EX_OK;
		}

		NSMutableArray* arg = [NSMutableArray array];
		for(size_t i = 0; i < argc; ++i)
			[arg addObject:@(argv[i])];

		NSDictionary* plist = @{
			kOakCommitWindowClientPortName: portName,
			kOakCommitWindowArguments:      arg,
			kOakCommitWindowEnvironment:    [[NSProcessInfo processInfo] environment],
		};

		NSString* serviceName = [NSString stringWithFormat:@"%@.CommitWindow.%@", NSProcessInfo.processInfo.environment[@"TM_APP_IDENTIFIER"], NSProcessInfo.processInfo.environment[@"TM_PID"]];
		if(!OakMessagePortSendRequest(serviceName, plist, 10))
		{
			fprintf(stderr, "%s: failed connecting to ‘%s’\n", getprogname(), serviceName.UTF8String);
			return EX_OK;
		}

		while(!result)
			CFRunLoopRun();

		if(NSString* err = result[kOakCommitWindowStandardError])
			fprintf(stderr, "%s", err.UTF8String);

		if(NSString* out = result[kOakCommitWindowStandardOutput])
		{
			fprintf(stdout, "%s", out.UTF8String);
			if([result[kOakCommitWindowContinue] boolValue])
				fprintf(stdout, "TM_SCM_COMMIT_CONTINUE=1\n");
		}

		[client invalidate];
		return [result[kOakCommitWindowReturnCode] intValue];
	}
}
