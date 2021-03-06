/*
 * Copyright 2010-present Facebook.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "FBError.h"
#import "FBGraphUser.h"
#import "FBIntegrationTests.h"
#import "FBRequest.h"
#import "FBSession+Internal.h"
#import "FBSessionTokenCachingStrategy.h"
#import "FBInternalSettings.h"
#import "FBTestBlocker.h"
#import "FBTestUserSession.h"
#import "FBUtility.h"

#if defined(FACEBOOKSDK_SKIP_SESSION_TESTS)

#pragma message ("warning: Skipping FBSessionIntegrationTests")

#else

@interface FBRequestConnection (FBSessionIntegrationTests)
+ (void)addRequestToRefreshPermissionsSession:(FBSession *)session connection:(FBRequestConnection *)connection;
@end

#pragma mark - Test suite

@interface FBSessionIntegrationTests : FBIntegrationTests
@end

@implementation FBSessionIntegrationTests

- (void)testSessionBasic
{
    FBConditionalLog(NO, FBLoggingBehaviorInformational, @"Testing conditional %@", @"log");
    FBConditionalLog(NO, FBLoggingBehaviorInformational, @"Testing conditional log");
    FBConditionalLog(YES, FBLoggingBehaviorInformational, @"%@", @"Testing conditional log");

    // create valid
    FBTestBlocker *blocker = [[[FBTestBlocker alloc] init] autorelease];

    FBTestUserSession *session = [self getTestSessionWithPermissions:nil];
    [session openWithCompletionHandler:^(FBSession *innerSession, FBSessionState status, NSError *error) {
        [blocker signal];
    } fromViewController:nil];

    XCTAssertTrue([blocker waitWithTimeout:30], @"blocker timed out");

    XCTAssertTrue(session.isOpen, @"Session should be valid, and is not");

    FBRequest *request = [[[FBRequest alloc] initWithSession:session
                                                   graphPath:@"me"]
                          autorelease];
    [request startWithCompletionHandler:
     ^(FBRequestConnection *connection, id<FBGraphUser> me, NSError *error) {
         XCTAssertTrue(me.objectID.length > 0, @"user id should be non-empty");
         [blocker signal];
     }];

    XCTAssertTrue([blocker waitWithTimeout:30], @"blocker timed out");

    [session close];
}

- (void)testSessionInvalidate
{
    // create valid
    FBTestBlocker *blocker = [[[FBTestBlocker alloc] init] autorelease];

    __block BOOL wasNotifiedOfInvalid = NO;
    // specify a permission to make sure we don't get the special open graph test user.
    FBTestUserSession *session = [self getTestSessionWithPermissions:@[@"user_likes"]];
    [session openWithCompletionHandler:^(FBSession *innerSession, FBSessionState status, NSError *error) {
        if (status == FBSessionStateClosed) {
            wasNotifiedOfInvalid = YES;
        }
        [blocker signal];
    } fromViewController:nil];
    XCTAssertTrue([blocker waitWithTimeout:30], @"blocker timed out");

    XCTAssertTrue(session.isOpen, @"Session should be open, and is not");

    __block NSString *userID = nil;
    FBRequest *request1 = [[[FBRequest alloc] initWithSession:session
                                                    graphPath:@"me"]
                           autorelease];
    [request1 startWithCompletionHandler:
     ^(FBRequestConnection *connection, id<FBGraphUser> me, NSError *error) {
         userID = [me.objectID retain];
         XCTAssertTrue(userID.length > 0, @"user id should be non-empty");
         [blocker signal];
     }];

    XCTAssertTrue([blocker waitWithTimeout:30], @"blocker timed out");

    // use FBRequest to create an NSURLRequest
    FBRequest *temp = [[FBRequest alloc] initWithSession:session
                                               graphPath:userID
                                              parameters:[NSDictionary dictionaryWithObjectsAndKeys:
                                                          @"delete", @"method",
                                                          nil]
                                              HTTPMethod:nil];
    FBRequestConnection *connection = [[FBRequestConnection alloc] init];
    [connection addRequest:temp completionHandler:nil];
    NSURLRequest *urlRequest = connection.urlRequest;
    [userID release];
    [connection release];
    [temp release];

    // synchronously delete the user
    NSURLResponse *response;
    NSError *error = nil;
    NSData *data;
    data = [NSURLConnection sendSynchronousRequest:urlRequest
                                 returningResponse:&response
                                             error:&error];
    // if !data or if data == false, log
    NSString *body = !data ? nil : [[[NSString alloc] initWithData:data
                                                          encoding:NSUTF8StringEncoding]
                                    autorelease];

    NSDictionary *jsonResponse = [FBUtility simpleJSONDecode:body];
    XCTAssertTrue([[jsonResponse valueForKey:@"success"] boolValue] == YES, @"body should return JSON {\"success\": true}");

    FBRequest *request2 = [[[FBRequest alloc] initWithSession:session
                                                    graphPath:@"me"]
                           autorelease];
    [request2 startWithCompletionHandler:
     ^(FBRequestConnection *innerConnection, id<FBGraphUser> me, NSError *innerError) {
         XCTAssertTrue(innerError != nil, @"response should be an error due to deleted user");
         [blocker signal];
     }];

    XCTAssertFalse(wasNotifiedOfInvalid, @"should not have invalidated the token yet");
    XCTAssertTrue([blocker waitWithTimeout:30], @"blocker timed out");
    XCTAssertTrue(wasNotifiedOfInvalid, @"should have invalidated the token by now");

    [session close];
}

- (void)testSessionOpenFromAccessToken
{
    FBTestBlocker *blocker = [[[FBTestBlocker alloc] init] autorelease];
    __block BOOL expectClosed = NO;

    // Open a test session normally for accesstoken/appid
    FBTestUserSession *normalSession = [self getTestSessionWithPermissions:nil];
    [normalSession openWithCompletionHandler:^(FBSession *session, FBSessionState status, NSError *error) {
        XCTAssertTrue(session.state == FBSessionStateOpen || expectClosed, @"Expected open session: %@, %@", session, error);
        [blocker signal];
    } fromViewController:nil];
    XCTAssertTrue([blocker waitWithTimeout:30], @"blocker timed out");

    // Now construct the actual session under test (target) and open with the access token.
    // Note just hack in expiration time of 3600 for the test.
    FBSession *target = [[FBSession alloc] initWithAppID:normalSession.appID permissions:nil
                                         defaultAudience:FBSessionDefaultAudienceFriends
                                         urlSchemeSuffix:nil
                                      tokenCacheStrategy:[FBSessionTokenCachingStrategy nullCacheInstance]];

    FBAccessTokenData *tokenDataCopy = [normalSession.accessTokenData copy];
    BOOL openResult = [target openFromAccessTokenData:tokenDataCopy
                                    completionHandler:^(FBSession *session, FBSessionState status, NSError *error) {
                                        XCTAssertTrue(status == FBSessionStateOpen || expectClosed,
                                                      @"status is :%lu , error:%@:",
                                                      (unsigned long)status,
                                                      error);
                                        [blocker signal];
                                    }];
    XCTAssertTrue(openResult, @"expected openResult=YES");
    XCTAssertTrue([blocker waitWithTimeout:30], @"blocker timed out");

    //final check, just do a request for me with the target
    FBRequest *request = [[[FBRequest alloc] initWithSession:target
                                                   graphPath:@"me"]
                          autorelease];
    [request startWithCompletionHandler:
     ^(FBRequestConnection *connection, id<FBGraphUser> me, NSError *error) {
         XCTAssertTrue(me.objectID.length > 0, @"user id should be non-empty. error:%@", error);
         [blocker signal];
     }];

    XCTAssertTrue([blocker waitWithTimeout:30], @"blocker timed out");

    expectClosed = YES;
    [target close];
    [normalSession close];
    [tokenDataCopy release];
    [target release];
}

- (void)testSessionOpenFromAccessTokenAlreadyOpen
{
    FBTestBlocker *blocker = [[[FBTestBlocker alloc] init] autorelease];
    __block BOOL expectClosed = NO;

    // Open a test session normally for accesstoken/appid
    FBTestUserSession *target = [self getTestSessionWithPermissions:nil];
    [target openWithCompletionHandler:^(FBSession *session, FBSessionState status, NSError *error) {
        XCTAssertTrue(session.state == FBSessionStateOpen || expectClosed, @"Expected open session: %@, %@", session, error);
        [blocker signal];
    } fromViewController:nil];
    XCTAssertTrue([blocker waitWithTimeout:30], @"blocker timed out");

    FBAccessTokenData *tokenDataCopy = [target.accessTokenData copy];

    //Now try to open it again
    XCTAssertThrowsSpecificNamed([target openFromAccessTokenData:tokenDataCopy
                                               completionHandler:^(FBSession *session, FBSessionState status, NSError *error) {
                                                   XCTFail(@"Completion handler was unexpectedly invoked for session: %@", session);
                                               }],
                                 NSException,
                                 FBInvalidOperationException);

    [tokenDataCopy release];
}

- (void)testSessionOpenWillRefreshPermissions
{
    FBTestBlocker *blocker = [[[FBTestBlocker alloc] init] autorelease];
    __block BOOL expectClosed = NO;

    // Open a test session normally for accesstoken/appid
    FBTestUserSession *normalSession = [self getTestSessionWithPermissions:nil];
    [normalSession openWithCompletionHandler:^(FBSession *session, FBSessionState status, NSError *error) {
        XCTAssertTrue(session.state == FBSessionStateOpen || expectClosed, @"Expected open session: %@, %@", session, error);
        [blocker signal];
    } fromViewController:nil];
    XCTAssertTrue([blocker waitWithTimeout:60], @"blocker timed out");
    XCTAssertTrue([normalSession shouldRefreshPermissions], @"expected need for permissions refresh");

    expectClosed = YES;
    [normalSession close];
}

- (void)testSessionOpenThenRefreshPermissions
{
    FBTestBlocker *blocker = [[[FBTestBlocker alloc] init] autorelease];
    __block BOOL expectClosed = NO;

    // Open a test session normally for accesstoken/appid
    FBTestUserSession *normalSession = [self getTestSessionWithPermissions:nil];
    [normalSession openWithCompletionHandler:^(FBSession *session, FBSessionState status, NSError *error) {
        XCTAssertTrue(session.state == FBSessionStateOpen || expectClosed, @"Expected open session: %@, %@", session, error);
        [blocker signal];
    } fromViewController:nil];
    XCTAssertTrue([blocker waitWithTimeout:60], @"blocker timed out");

    // Now ask for permissions refresh, and verify that the piggyback will not be added.
    id mockConnection = [OCMockObject niceMockForClass:[FBRequestConnection class]];
    [[mockConnection reject] addRequestToRefreshPermissionsSession:OCMOCK_ANY connection:OCMOCK_ANY];

    blocker = [[[FBTestBlocker alloc] init] autorelease];
    [normalSession refreshPermissionsWithCompletionHandler:^(FBSession *session, NSError *error) {
        XCTAssertNil(error, @"unexpected error refreshing permissions");
        [blocker signal];
    }];
    XCTAssertTrue([blocker waitWithTimeout:20], @"blocker timed out for permissions refresh");
    [mockConnection verify];

    expectClosed = YES;
    [normalSession close];
}

- (void)testSessionOpenFromAccessTokenWillRefreshPermissions
{
    FBTestBlocker *blocker = [[[FBTestBlocker alloc] init] autorelease];
    __block BOOL expectClosed = NO;

    // Open a test session normally for accesstoken/appid
    FBTestUserSession *normalSession = [self getTestSessionWithPermissions:nil];
    [normalSession openWithCompletionHandler:^(FBSession *session, FBSessionState status, NSError *error) {
        XCTAssertTrue(session.state == FBSessionStateOpen || expectClosed, @"Expected open session: %@, %@", session, error);
        [blocker signal];
    } fromViewController:nil];
    XCTAssertTrue([blocker waitWithTimeout:60], @"blocker timed out");

    // Now construct the actual session under test (target) and open with the access token.
    // Note just hack in expiration time of 3600 for the test.
    FBSession *target = [[FBSession alloc] initWithAppID:normalSession.appID permissions:nil
                                         defaultAudience:FBSessionDefaultAudienceFriends
                                         urlSchemeSuffix:nil
                                      tokenCacheStrategy:[FBSessionTokenCachingStrategy nullCacheInstance]];

    FBAccessTokenData *tokenDataCopy = [normalSession.accessTokenData copy];
    BOOL openResult = [target openFromAccessTokenData:tokenDataCopy
                                    completionHandler:^(FBSession *session, FBSessionState status, NSError *error) {
                                        XCTAssertTrue(status == FBSessionStateOpen || expectClosed,
                                                      @"status is :%lu, error:%@:",
                                                      (unsigned long)status,
                                                      error);
                                        [blocker signal];
                                    }];
    XCTAssertTrue(openResult, @"expected openResult=YES");
    XCTAssertTrue([blocker waitWithTimeout:10], @"blocker timed out");

    // Check the refresh permissions state
    XCTAssertTrue([target shouldRefreshPermissions], @"expected need for permissions refresh");

    //now do a request for me with the target which will refresh the permissions
    FBRequest *request = [[[FBRequest alloc] initWithSession:target
                                                   graphPath:@"me"]
                          autorelease];
    [request startWithCompletionHandler:
     ^(FBRequestConnection *connection, id<FBGraphUser> me, NSError *error) {
         XCTAssertTrue(me.objectID.length > 0, @"user id should be non-empty. error:%@", error);
         [blocker signal];
     }];

    XCTAssertTrue([blocker waitWithTimeout:30], @"blocker timed out requesting me");

    // now make sure the refresh permissions is satisfied.
    XCTAssertFalse([target shouldRefreshPermissions], @"did NOT expect need for permissions refresh");

    expectClosed = YES;
    [target close];
    [normalSession close];
}

- (void)testSessionOpenFromTokenAndCheckUserID
{
    FBConditionalLog(NO, FBLoggingBehaviorInformational, @"Testing conditional %@", @"log");
    FBConditionalLog(NO, FBLoggingBehaviorInformational, @"Testing conditional log");
    FBConditionalLog(YES, FBLoggingBehaviorInformational, @"%@", @"Testing conditional log");

    FBTestBlocker *blocker = [[[FBTestBlocker alloc] init] autorelease];


    // Open a test session normally for accesstoken/appid
    FBTestUserSession *normalSession = [self getTestSessionWithPermissions:nil];
    [normalSession openWithCompletionHandler:^(FBSession *session, FBSessionState status, NSError *error) {
        if (status == FBSessionStateOpen) {
            [blocker signal];
        }
    } fromViewController:nil];
    XCTAssertTrue([blocker waitWithTimeout:10], @"blocker timed out");

    FBAccessTokenData *token = [FBAccessTokenData createTokenFromString:normalSession.accessTokenData.accessToken
                                                            permissions:nil
                                                    declinedPermissions:nil
                                                         expirationDate:[NSDate distantFuture]
                                                              loginType:FBSessionLoginTypeFacebookApplication
                                                            refreshDate:[NSDate dateWithTimeIntervalSince1970:0]
                                                 permissionsRefreshDate:nil
                                                                  appID:[self testAppId]
                                                                 userID:@"4"];
    FBTestUserSession *session = [FBTestUserSession sessionWithAccessTokenData:token];

    [session openFromAccessTokenData:token completionHandler:^(FBSession *session3, FBSessionState status, NSError *error) {
        if (status == FBSessionStateOpen) {
            XCTAssertTrue([@"4" isEqualToString:session.accessTokenData.userID]);
            [blocker signal];
        }
    }];

    [blocker waitWithTimeout:10];

    XCTAssertTrue(session.isOpen, @"Session should be valid, and is not");

    [session requestNewPublishPermissions:@[@"publish_actions"] defaultAudience:FBSessionDefaultAudienceOnlyMe completionHandler:^(FBSession *session2, NSError *error) {
        XCTAssertTrue([@"4" isEqualToString:session.accessTokenData.userID]);
        [blocker signal];
    }];
    [blocker waitWithTimeout:10];

    XCTAssertTrue([@"4" isEqualToString:session.accessTokenData.userID]);
    [session close];
}


@end

#endif

