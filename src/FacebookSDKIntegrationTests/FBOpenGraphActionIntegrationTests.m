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

#import "FBGraphPlace.h"
#import "FBGraphUser.h"
#import "FBIntegrationTests.h"
#import "FBOpenGraphAction.h"
#import "FBRequest.h"
#import "FBRequestConnection.h"
#import "FBTestBlocker.h"
#import "FBTestUserSession.h"

@protocol FBOGTestObject<FBGraphObject>

@property (retain, nonatomic) NSString *title;
@property (retain, nonatomic) NSString *url;

@end

@protocol FBOGRunTestAction<FBOpenGraphAction>

@property (retain, nonatomic) id<FBOGTestObject> test;

@end


// Open Graph namespaces must be unique, so running these tests against specific
// Facebook Applications will require choosing a new namespace.
#define UNIT_TEST_OPEN_GRAPH_NAMESPACE "facebooksdktests"

#if defined(FACEBOOKSDK_SKIP_OPEN_GRAPH_ACTION_TESTS) || !defined(UNIT_TEST_OPEN_GRAPH_NAMESPACE)

#pragma message ("warning: Skipping FBOpenGraphActionTests")

#else

@interface FBOpenGraphActionIntegrationTests : FBIntegrationTests
@end

@implementation FBOpenGraphActionIntegrationTests

- (id<FBOGTestObject>)openGraphTestObject:(NSString *)testName {
    // We create an FBGraphObject object, but we can treat it as an SCOGMeal with typed
    // properties, etc. See <FacebookSDK/FBGraphObject.h> for more details.
    id<FBOGTestObject> result = (id<FBOGTestObject>)[FBGraphObject graphObject];

    // Give it a URL of sample data that contains the object's name, title, description, and body.
    if ([testName isEqualToString:@"testPostingSimpleOpenGraphAction"]) {
        result.url = @"http://samples.ogp.me/414237771945858";
    } else if ([testName isEqualToString:@"testPostingComplexOpenGraphAction"]) {
        result.url = @"http://samples.ogp.me/414238245279144";
    }
    return result;
}

- (void)testPostingSimpleOpenGraphAction {
    id<FBOGTestObject> testObject = [self openGraphTestObject:@"testPostingSimpleOpenGraphAction"];

    id<FBOGRunTestAction> action = (id<FBOGRunTestAction>)[FBGraphObject graphObject];
    action.test = testObject;

    FBTestUserSession *session = [self getTestSessionWithPermissions:@[@"publish_actions"]];
    [self loginSession:session];
    [self postAndValidateWithSession:session
                           graphPath:@"me/"UNIT_TEST_OPEN_GRAPH_NAMESPACE":run"
                         graphObject:action
                       hasProperties:[NSArray array]];

}

- (id<FBOGRunTestAction>)createComplexOpenGraphAction:(NSString *)taggedUserID {
    id<FBOGTestObject> testObject = [self openGraphTestObject:@"testPostingComplexOpenGraphAction"];

    id<FBGraphUser> userObject = (id<FBGraphUser>)[FBGraphObject graphObject];
    userObject.objectID = taggedUserID;

    id<FBOGRunTestAction> action = (id<FBOGRunTestAction>)[FBGraphObject graphObject];
    action.test = testObject;
    action.tags = [NSArray arrayWithObject:userObject];

    NSDictionary *image = [NSDictionary dictionaryWithObjectsAndKeys:
                           @"https://sphotos-b.xx.fbcdn.net/hphotos-ash4/387972_10152013102225492_1756755651_n.jpg", @"url",
                           nil];
    NSArray *images = [NSArray arrayWithObject:image];
    action.image = images;

    return action;
}

- (void)testPostingComplexOpenGraphAction {
    NSArray *sessions = [self getTestSessionsWithPermissions:@[@"publish_actions"] count:2];
    FBSession *session1 = [self loginSession:sessions[0]];
    FBSession *session2 = [self loginSession:sessions[1]];
    [self makeTestUserInSession:session1 friendsWithTestUserInSession:session2];

    id<FBOGRunTestAction> action = [self createComplexOpenGraphAction:session2.accessTokenData.userID];

    [self postAndValidateWithSession:session1
                           graphPath:@"me/"UNIT_TEST_OPEN_GRAPH_NAMESPACE":run"
                         graphObject:action
                       hasProperties:[NSArray arrayWithObjects:
                                      @"image",
                                      @"tags",
                                      nil]];
}

- (void)testPostingComplexOpenGraphActionInBatch {
    NSArray *sessions = [self getTestSessionsWithPermissions:@[@"publish_actions"] count:2];
    FBSession *session1 = [self loginSession:sessions[0]];
    FBSession *session2 = [self loginSession:sessions[1]];

    [self makeTestUserInSession:session1 friendsWithTestUserInSession:session2];

    id<FBOGRunTestAction> action = [self createComplexOpenGraphAction:session2.accessTokenData.userID];

    id postedAction = [self batchedPostAndGetWithSession:session1 graphPath:@"me/"UNIT_TEST_OPEN_GRAPH_NAMESPACE":run" graphObject:action];
    XCTAssertNotNil(postedAction, @"nil postedAction");

    [self validateGraphObject:postedAction
                hasProperties:[NSArray arrayWithObjects:
                               @"image",
                               @"tags",
                               nil]];
}

- (void)testPostingUserGeneratedImageInAction
{
    id<FBOGTestObject> testObject = [self openGraphTestObject:@"testPostingSimpleOpenGraphAction"];

    id<FBOGRunTestAction> action = (id<FBOGRunTestAction>)[FBGraphObject graphObject];
    action.test = testObject;

    // Note: we pass user_generated=false rather than true because apps must be approved for
    // user-generated photos and that's extra work for the unit-test-app creator. false achieves
    // the same goal (just checking that it was round-tripped).
    NSDictionary *image = [NSDictionary dictionaryWithObjectsAndKeys:
                           @"false", @"user_generated",
                           @"https://sphotos-b.xx.fbcdn.net/hphotos-ash4/387972_10152013102225492_1756755651_n.jpg", @"url",
                           nil];
    NSArray *images = [NSArray arrayWithObject:image];
    action.image = images;

    FBSession *session = [self loginSession:[self getTestSessionWithPermissions:@[@"publish_actions"]]];
    id postedAction = [self batchedPostAndGetWithSession:session
                                               graphPath:@"me/"UNIT_TEST_OPEN_GRAPH_NAMESPACE":run"
                                             graphObject:action];
    XCTAssertNotNil(postedAction, @"nil postedAction");

    NSArray *postedImages = [postedAction objectForKey:@"image"];
    XCTAssertNotNil(postedImages, @"nil images");
    XCTAssertTrue(1 == postedImages.count, @"not 1 image");

    id<FBGraphObject> postedImage = [postedImages objectAtIndex:0];
    [self validateGraphObject:postedImage hasProperties:[NSArray arrayWithObjects:
                                                         @"url",
                                                         @"user_generated",
                                                         nil]];
}

@end

#endif
