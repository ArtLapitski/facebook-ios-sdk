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

#import <objc/runtime.h>

#import "FBAccessTokenData+Internal.h"
#import "FBAuthenticationTests.h"
#import "FBError.h"
#import "FBSession.h"
#import "FBTestBlocker.h"
#import "FBUtility.h"

@interface FBFacebookAppAuthenticationTests : FBAuthenticationTests
@end

@implementation FBFacebookAppAuthenticationTests
{
    Method _originalIsRegisteredCheck;
    Method _swizzledIsRegisteredCheck;
}

+ (BOOL)isRegisteredURLSchemeReplacement:(NSString *)url
{
    return YES;
}

- (void)setUp {
    [super setUp];
    _originalIsRegisteredCheck = class_getClassMethod([FBUtility class], @selector(isRegisteredURLScheme:));
    _swizzledIsRegisteredCheck = class_getClassMethod([self class], @selector(isRegisteredURLSchemeReplacement:));
    method_exchangeImplementations(_originalIsRegisteredCheck, _swizzledIsRegisteredCheck);
}

- (void)tearDown {
    [super tearDown];
    method_exchangeImplementations(_swizzledIsRegisteredCheck, _originalIsRegisteredCheck);
    _originalIsRegisteredCheck = nil;
    _swizzledIsRegisteredCheck = nil;
}

- (void)testOpenTriesFacebookAppAuthFirstWithFallbackToWebView {
    [self testImplOpenTriesFacebookAppAuthFirstWithBehavior:FBSessionLoginBehaviorWithFallbackToWebView];
}

- (void)testOpenTriesFacebookAppAuthFirstWithNoFallbackToWebView {
    [self testImplOpenTriesFacebookAppAuthFirstWithBehavior:FBSessionLoginBehaviorWithNoFallbackToWebView];
}

- (void)testImplOpenTriesFacebookAppAuthFirstWithBehavior:(FBSessionLoginBehavior)behavior {
    FBSession *mockSession = [OCMockObject partialMockForObject:[FBSession alloc]];
    
    [self mockSession:mockSession supportSystemAccount:YES];
    [self mockSession:mockSession expectSystemAccountAuth:NO succeed:NO];
    [self mockSession:mockSession supportMultitasking:YES];
    [self mockSession:mockSession expectFacebookAppAuth:YES try:YES results:nil];
    [self mockSession:mockSession expectSafariAuth:NO try:NO results:nil];
    [self mockSession:mockSession expectLoginDialogAuth:NO succeed:NO];
    
    FBSession *session = [mockSession initWithAppID:kAuthenticationTestAppId
                                        permissions:nil
                                    defaultAudience:FBSessionDefaultAudienceNone
                                    urlSchemeSuffix:nil
                                 tokenCacheStrategy:nil];
    
    [session openWithBehavior:behavior
           fromViewController:nil
            completionHandler:nil];
    
    [(id)mockSession verify];
    
    [session release];
}

- (void)testOpenDoesNotTryFacebookAppAuthWithSystemAccount {
    [self testImplOpenDoesNotTryFacebookAppAuthWithBehavior:FBSessionLoginBehaviorUseSystemAccountIfPresent
                                               expectSystem:YES];
}

- (void)testOpenDoesNotTryFacebookAppAuthWithForcingWebView {
    [self testImplOpenDoesNotTryFacebookAppAuthWithBehavior:FBSessionLoginBehaviorForcingWebView
                                               expectSystem:NO];
}

- (void)testImplOpenDoesNotTryFacebookAppAuthWithBehavior:(FBSessionLoginBehavior)behavior
                                             expectSystem:(BOOL)expectSystem {
    FBSession *mockSession = [OCMockObject partialMockForObject:[FBSession alloc]];
    
    [self mockSession:mockSession supportSystemAccount:YES];
    [self mockSession:mockSession expectSystemAccountAuth:expectSystem succeed:NO];
    [self mockSession:mockSession supportMultitasking:YES];
    [self mockSession:mockSession expectFacebookAppAuth:NO try:NO results:nil];
    [self mockSession:mockSession expectSafariAuth:NO try:NO results:nil];
    [self mockSession:mockSession expectLoginDialogAuth:!expectSystem succeed:NO];
    
    FBSession *session = [mockSession initWithAppID:kAuthenticationTestAppId
                                        permissions:nil
                                    defaultAudience:FBSessionDefaultAudienceNone
                                    urlSchemeSuffix:nil
                                 tokenCacheStrategy:nil];
    
    [session openWithBehavior:behavior
           fromViewController:nil
            completionHandler:nil];
    
    [(id)mockSession verify];
    
    [session release];
}

// The following tests validate that a successful results results in an open session,
// for each login behavior that is appropriate.
- (void)testFacebookAppAuthSuccessWithFallbackToWebView {
    [self testImplFacebookAppAuthSuccessWithBehavior:FBSessionLoginBehaviorWithFallbackToWebView];
}

- (void)testFacebookAppAuthSuccessWithNoFallbackToWebView {
    [self testImplFacebookAppAuthSuccessWithBehavior:FBSessionLoginBehaviorWithNoFallbackToWebView];
}

- (void)testFacebookAppAuthSuccessWithUseSystemAccount {
    [self testImplFacebookAppAuthSuccessWithBehavior:FBSessionLoginBehaviorUseSystemAccountIfPresent];
}

- (void)testImplFacebookAppAuthSuccessWithBehavior:(FBSessionLoginBehavior)behavior {
    FBSession *mockSession = [OCMockObject partialMockForObject:[FBSession alloc]];
    
    // We'll build a URL out of these results and send it back through handleOpenURL.
    NSDictionary *results = [NSDictionary dictionaryWithObjectsAndKeys:
                             kAuthenticationTestValidToken, @"access_token",
                             @"3600", @"expires_in",
                             nil];
    
    [self mockSession:mockSession supportSystemAccount:NO];
    [self mockSession:mockSession expectSystemAccountAuth:NO succeed:NO];
    [self mockSession:mockSession supportMultitasking:YES];
    [self mockSession:mockSession expectFacebookAppAuth:YES try:YES results:results];
    [self mockSession:mockSession expectSafariAuth:NO try:NO results:nil];
    [self mockSession:mockSession expectLoginDialogAuth:NO succeed:NO];
    
    FBSession *session = [mockSession initWithAppID:kAuthenticationTestAppId
                                        permissions:nil
                                    defaultAudience:FBSessionDefaultAudienceNone
                                    urlSchemeSuffix:nil
                                 tokenCacheStrategy:nil];
    
    __block BOOL handlerCalled = NO;
    [session openWithBehavior:behavior
           fromViewController:nil
            completionHandler:^(FBSession *innerSession, FBSessionState status, NSError *error) {
        handlerCalled = YES;
        [_blocker signal];
    }];
    
    XCTAssertTrue([_blocker waitWithTimeout:1], @"blocker timed out");
    
    [(id)mockSession verify];

    XCTAssertTrue(handlerCalled);
    XCTAssertEqual(FBSessionStateOpen, mockSession.state);
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    XCTAssertTrue([kAuthenticationTestValidToken isEqualToString:mockSession.accessToken]);
    XCTAssertEqual(FBSessionLoginTypeFacebookApplication, mockSession.loginType);
    // TODO assert expiration date is what we set it to (within delta)
    
    [session release];
}

// The following tests validate that the 'service_disabled_use_browser' error response results
// in Safari auth being attempted, for each login behavior that is appropriate.
- (void)testFacebookAppAuthDisabledTriesSafariWithFallbackToWebView {
    [self testFacebookAppAuthDisabledTriesSafariWithBehavior:FBSessionLoginBehaviorWithFallbackToWebView];
}

- (void)testFacebookAppAuthDisabledTriesSafariWithNoFallbackToWebView {
    [self testFacebookAppAuthDisabledTriesSafariWithBehavior:FBSessionLoginBehaviorWithNoFallbackToWebView];
}

- (void)testFacebookAppAuthDisabledTriesSafariWithUseSystemAccount {
    [self testFacebookAppAuthDisabledTriesSafariWithBehavior:FBSessionLoginBehaviorUseSystemAccountIfPresent];
}

- (void)testFacebookAppAuthDisabledTriesSafariWithBehavior:(FBSessionLoginBehavior)behavior {
    FBSession *mockSession = [OCMockObject partialMockForObject:[FBSession alloc]];
    
    // We'll build a URL out of these results and send it back through handleOpenURL.
    NSDictionary *results = [NSDictionary dictionaryWithObjectsAndKeys:
                             @"service_disabled_use_browser", @"error",
                             nil];
    
    [self mockSession:mockSession supportSystemAccount:NO];
    [self mockSession:mockSession expectSystemAccountAuth:NO succeed:NO];
    [self mockSession:mockSession supportMultitasking:YES];
    [self mockSession:mockSession expectFacebookAppAuth:YES try:YES results:results];
    [self mockSession:mockSession expectSafariAuth:YES try:YES results:nil];
    [self mockSession:mockSession expectLoginDialogAuth:NO succeed:NO];
    
    FBSession *session = [mockSession initWithAppID:kAuthenticationTestAppId
                                        permissions:nil
                                    defaultAudience:FBSessionDefaultAudienceNone
                                    urlSchemeSuffix:nil
                                 tokenCacheStrategy:nil];
    
    [session openWithBehavior:FBSessionLoginBehaviorWithNoFallbackToWebView completionHandler:nil];
    
    [_blocker waitWithTimeout:.01];
    
    [(id)mockSession verify];
    
    [session release];
}


// The following tests validate that the 'service_disabled' error response results
// in a login dialog auth being attempted, for each login behavior that is appropriate.

// TODO: these do not work as expected; should FBSession be calling with fallback:YES?
/*
 - (void)testFacebookAppAuthDisabledTriesLoginDialogWithFallbackToWebView {
 [self testFacebookAppAuthDisabledTriesLoginDialogWithBehavior:FBSessionLoginBehaviorWithFallbackToWebView];
 }
 
 - (void)testFacebookAppAuthDisabledTriesLoginDialogWithNoFallbackToWebView {
 [self testFacebookAppAuthDisabledTriesLoginDialogWithBehavior:FBSessionLoginBehaviorWithNoFallbackToWebView];
 }
 
 - (void)testFacebookAppAuthDisabledTriesLoginDialogWithUseSystemAccount {
 [self testFacebookAppAuthDisabledTriesLoginDialogWithBehavior:FBSessionLoginBehaviorUseSystemAccountIfPresent];
 }
 */

- (void)testFacebookAppAuthDisabledTriesLoginDialogWithBehavior:(FBSessionLoginBehavior)behavior {
    FBSession *mockSession = [OCMockObject partialMockForObject:[FBSession alloc]];
    
    // We'll build a URL out of these results and send it back through handleOpenURL.
    NSDictionary *results = [NSDictionary dictionaryWithObjectsAndKeys:
                             @"service_disabled", @"error",
                             nil];
    
    [self mockSession:mockSession supportSystemAccount:NO];
    [self mockSession:mockSession expectSystemAccountAuth:NO succeed:NO];
    [self mockSession:mockSession supportMultitasking:YES];
    [self mockSession:mockSession expectFacebookAppAuth:YES try:YES results:results];
    [self mockSession:mockSession expectSafariAuth:NO try:NO results:nil];
    [self mockSession:mockSession expectLoginDialogAuth:YES succeed:NO];
    
    FBSession *session = [mockSession initWithAppID:kAuthenticationTestAppId
                                        permissions:nil
                                    defaultAudience:FBSessionDefaultAudienceNone
                                    urlSchemeSuffix:nil
                                 tokenCacheStrategy:nil];
    
    [session openWithBehavior:FBSessionLoginBehaviorWithNoFallbackToWebView completionHandler:nil];
    
    [_blocker waitWithTimeout:.01];
    
    [(id)mockSession verify];
    
    [session release];
}

 // The following tests validate that a successful results results in an open session,
 // for each login behavior that is appropriate.
 - (void)testFacebookAppAuthErrorWithFallbackToWebView {
 [self testImplFacebookAppAuthErrorWithBehavior:FBSessionLoginBehaviorWithFallbackToWebView];
 }
 
 - (void)testFacebookAppAuthErrorWithNoFallbackToWebView {
 [self testImplFacebookAppAuthErrorWithBehavior:FBSessionLoginBehaviorWithNoFallbackToWebView];
 }
 
 - (void)testFacebookAppAuthErrorWithUseSystemAccount {
 [self testImplFacebookAppAuthErrorWithBehavior:FBSessionLoginBehaviorUseSystemAccountIfPresent];
 }

- (void)testImplFacebookAppAuthErrorWithBehavior:(FBSessionLoginBehavior)behavior {
    FBSession *mockSession = [OCMockObject partialMockForObject:[FBSession alloc]];
    
    // We'll build a URL out of these results and send it back through handleOpenURL.
    NSDictionary *results = [NSDictionary dictionaryWithObjectsAndKeys:
                             @"an error code", @"error_code",
                             @"an error reason", @"error",
                             nil];
    
    [self mockSession:mockSession supportSystemAccount:NO];
    [self mockSession:mockSession expectSystemAccountAuth:NO succeed:NO];
    [self mockSession:mockSession supportMultitasking:YES];
    [self mockSession:mockSession expectFacebookAppAuth:YES try:YES results:results];
    [self mockSession:mockSession expectSafariAuth:NO try:NO results:nil];
    [self mockSession:mockSession expectLoginDialogAuth:NO succeed:NO];
    
    FBSession *session = [mockSession initWithAppID:kAuthenticationTestAppId
                                        permissions:nil
                                    defaultAudience:FBSessionDefaultAudienceNone
                                    urlSchemeSuffix:nil
                                 tokenCacheStrategy:nil];
    
    __block BOOL handlerCalled = NO;
    __block NSError *handlerError = nil;
    [session openWithBehavior:behavior completionHandler:^(FBSession *innerSession, FBSessionState status, NSError *error) {
        handlerCalled = YES;
        handlerError = [error retain];
        [_blocker signal];
    }];
    
    [_blocker waitWithTimeout:.01];
    
    [(id)mockSession verify];

    XCTAssertTrue(handlerCalled);
    XCTAssertEqual(FBSessionStateClosedLoginFailed, mockSession.state);
    XCTAssertNotNil(handlerError);

    [session release];
}
/*
- (void)testReauthorizeSuccess {
    FBSession *mockSession = [OCMockObject partialMockForObject:[FBSession alloc]];
    
    // We'll build a URL out of these results and send it back through handleOpenURL.
    NSDictionary *results = [NSDictionary dictionaryWithObjectsAndKeys:
                             kAuthenticationTestValidToken, @"access_token",
                             @"3600", @"expires_in",
                             nil];
    
    [self mockSession:mockSession supportSystemAccount:NO];
    [self mockSession:mockSession expectSystemAccountAuth:NO succeed:NO];
    [self mockSession:mockSession supportMultitasking:YES];
    [self mockSession:mockSession expectFacebookAppAuth:YES try:YES results:results];
    [self mockSession:mockSession expectSafariAuth:NO try:NO results:nil];
    [self mockSession:mockSession expectLoginDialogAuth:NO succeed:NO];
    
    FBSession *session = [mockSession initWithAppID:kAuthenticationTestAppId
                                        permissions:nil
                                    defaultAudience:FBSessionDefaultAudienceNone
                                    urlSchemeSuffix:nil
                                 tokenCacheStrategy:nil];
    
    __block BOOL handlerCalled = NO;
    [session openWithBehavior:FBSessionLoginBehaviorWithNoFallbackToWebView completionHandler:^(FBSession *session, FBSessionState status, NSError *error) {
        handlerCalled = YES;
        [_blocker signal];
    }];
    
    [_blocker waitWithTimeout:.01];
    
    results = [NSDictionary dictionaryWithObjectsAndKeys:
               @"anewtoken", @"access_token",
               @"3600", @"expires_in",
               nil];

    [self mockSession:mockSession supportSystemAccount:NO];
    [self mockSession:mockSession expectSystemAccountAuth:NO succeed:NO];
    [self mockSession:mockSession supportMultitasking:YES];
    [self mockSession:mockSession expectFacebookAppAuth:YES try:YES results:results];
    
    NSArray *requestedPermissions = [NSArray arrayWithObjects:@"perm1", @"perm2", nil];
    [session requestNewReadPermissions:requestedPermissions completionHandler:^(FBSession *session, NSError *error) {
        [_blocker signal];
    }];

    [_blocker waitWithTimeout:.01];
    
    XCTAssertTrue(handlerCalled);
    XCTAssertEqual(FBSessionStateOpen, session.state);
    assertThat(session.accessToken, equalTo(@"anewtoken"));
    XCTAssertEqual(FBSessionLoginTypeFacebookApplication, session.loginType);
//    assertThat(session.permissions, contains(@"perm1", @"perm2", nil));
    
    [session release];
}
*/
#pragma mark handleDidBecomeActive tests

// [FBSession handleDidBecomeActive] isn't specifically related to Facebook app authentication,
// but it is simpler to test it using the infrastructure we have in this class.

- (void)testHandleDidBecomeActiveDuringAuth {
    FBSession *mockSession = [OCMockObject partialMockForObject:[FBSession alloc]];
    
    [self mockSession:mockSession supportSystemAccount:NO];
    [self mockSession:mockSession expectSystemAccountAuth:NO succeed:NO];
    [self mockSession:mockSession supportMultitasking:YES];
    [self mockSession:mockSession expectFacebookAppAuth:YES try:YES results:nil];
    [self mockSession:mockSession expectSafariAuth:NO try:NO results:nil];
    [self mockSession:mockSession expectLoginDialogAuth:NO succeed:NO];
    
    FBSession *session = [mockSession initWithAppID:kAuthenticationTestAppId
                                        permissions:nil
                                    defaultAudience:FBSessionDefaultAudienceNone
                                    urlSchemeSuffix:nil
                                 tokenCacheStrategy:nil];
    [session openWithBehavior:FBSessionLoginBehaviorWithNoFallbackToWebView completionHandler:nil];
    
    [_blocker waitWithTimeout:.01];
    
    [(id)mockSession verify];

    XCTAssertEqual(FBSessionStateCreatedOpening, mockSession.state);
    
    [session handleDidBecomeActive];
    
    XCTAssertEqual(FBSessionStateClosedLoginFailed, session.state);
    XCTAssertFalse([session.permissions containsObject:@"permission1"]);

    [session release];
}

- (void)testHandleDidBecomeActiveDuringReauth {
    FBSession *mockSession = [OCMockObject partialMockForObject:[FBSession alloc]];
    
    // First time through, we want valid results
    NSDictionary *results = [NSDictionary dictionaryWithObjectsAndKeys:
                             kAuthenticationTestValidToken, @"access_token",
                             @"3600", @"expires_in",
                             nil];

    [self mockSession:mockSession supportSystemAccount:NO];
    [self mockSession:mockSession expectSystemAccountAuth:NO succeed:NO];
    [self mockSession:mockSession supportMultitasking:YES];
    [self mockSession:mockSession expectFacebookAppAuth:YES try:YES results:results];
    [self mockSession:mockSession expectSafariAuth:NO try:NO results:nil];
    [self mockSession:mockSession expectLoginDialogAuth:NO succeed:NO];
    
    FBSession *session = [mockSession initWithAppID:kAuthenticationTestAppId
                                        permissions:nil
                                    defaultAudience:FBSessionDefaultAudienceNone
                                    urlSchemeSuffix:nil
                                 tokenCacheStrategy:nil];
    [session openWithBehavior:FBSessionLoginBehaviorWithNoFallbackToWebView completionHandler:nil];
    
    [_blocker waitWithTimeout:.01];
    
    [(id)mockSession verify];

    XCTAssertEqual(FBSessionStateOpen, mockSession.state);
    
    // On the reauth, don't provide results, which will simulate a reauth that is still in progress.
    [self mockSession:mockSession expectFacebookAppAuth:YES try:YES results:nil];

    NSArray *requestedPermissions = [NSArray arrayWithObjects:@"permission1", nil];
    __block NSError *handlerError = nil;
    [session requestNewReadPermissions:requestedPermissions
                     completionHandler:^(FBSession *innerSession, NSError *error) {
        handlerError = error;
    }];

    [session handleDidBecomeActive];

    XCTAssertNotNil(handlerError);
    XCTAssertEqual(FBSessionStateOpen, session.state);
    XCTAssertFalse([session.permissions containsObject:@"permission1"]);
    
    [session release];
}

// TODO finish Facebook app auth tests

@end
