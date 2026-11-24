#import "../src/OakMessagePort.h"

static NSString* unique_name (char const* suffix)
{
	return [NSString stringWithFormat:@"com.macromates.test.message-port.%d.%s", getpid(), suffix];
}

// A request and its reply travel as property lists; the server answers on
// the thread that created it, which here is the one waiting for the reply.
void test_request_and_reply_round_trip ()
{
	NSString* name = unique_name("roundtrip");
	__block NSDictionary* received;
	OakMessagePortServer* server = [[OakMessagePortServer alloc] initWithName:name handler:^NSDictionary*(NSDictionary* request){
		received = request;
		return @{ @"returnCode": @7, @"echo": request[@"arguments"] };
	}];
	OAK_ASSERT(server);

	NSDictionary* reply = OakMessagePortSendRequest(name, @{ @"arguments": @[ @"commit", @"-m", @"msg" ], @"environment": @{ @"TM_PID": @"42" } }, 2);
	OAK_ASSERT(reply);
	OAK_ASSERT([received[@"arguments"] isEqualToArray:(@[ @"commit", @"-m", @"msg" ])]);
	OAK_ASSERT([received[@"environment"][@"TM_PID"] isEqualToString:@"42"]);
	OAK_ASSERT_EQ([reply[@"returnCode"] intValue], 7);
	OAK_ASSERT([reply[@"echo"] isEqualToArray:(@[ @"commit", @"-m", @"msg" ])]);

	[server invalidate];
}

void test_server_without_reply_data_yields_an_empty_dictionary ()
{
	NSString* name = unique_name("noreply");
	OakMessagePortServer* server = [[OakMessagePortServer alloc] initWithName:name handler:^NSDictionary*(NSDictionary*){ return nil; }];
	NSDictionary* reply = OakMessagePortSendRequest(name, @{ @"ping": @YES }, 2);
	OAK_ASSERT(reply);
	OAK_ASSERT_EQ(reply.count, 0);
	[server invalidate];
}

void test_missing_server_yields_nil ()
{
	OAK_ASSERT(OakMessagePortSendRequest(unique_name("nobody-home"), @{ }, 1) == nil);
}

void test_a_taken_name_cannot_be_registered_twice ()
{
	NSString* name = unique_name("taken");
	OakMessagePortServer* first = [[OakMessagePortServer alloc] initWithName:name handler:^NSDictionary*(NSDictionary*){ return nil; }];
	OAK_ASSERT(first);
	OakMessagePortServer* second = [[OakMessagePortServer alloc] initWithName:name handler:^NSDictionary*(NSDictionary*){ return nil; }];
	OAK_ASSERT(second == nil);
	[first invalidate];

	// Once invalidated the name is free again
	OakMessagePortServer* third = [[OakMessagePortServer alloc] initWithName:name handler:^NSDictionary*(NSDictionary*){ return nil; }];
	OAK_ASSERT(third);
	[third invalidate];
}
