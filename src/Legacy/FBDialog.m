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

#import "FBDialog.h"

#import "FBAppCall+Internal.h"
#import "FBDialogClosePNG.h"
#import "FBFrictionlessRequestSettings.h"
#import "FBSettings+Internal.h"
#import "FBUtility.h"
#import "Facebook.h"

#if TARGET_OS_IPHONE
int const FBFlexibleWidth = UIViewAutoresizingFlexibleWidth;
int const FBFlexibleHeight = UIViewAutoresizingFlexibleHeight;
int const FBFlexibleMargins = UIViewAutoresizingFlexibleTopMargin
                            | UIViewAutoresizingFlexibleBottomMargin
                            | UIViewAutoresizingFlexibleLeftMargin
                            | UIViewAutoresizingFlexibleRightMargin;
#elif TARGET_OS_MAC
int const FBFlexibleWidth = NSViewWidthSizable;
int const FBFlexibleHeight = NSViewHeightSizable;
int const FBFlexibleMargins = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin;
#endif

///////////////////////////////////////////////////////////////////////////////////////////////////
// global

static CGFloat kBorderGray[4] = {0.3, 0.3, 0.3, 0.8};
static CGFloat kBorderBlack[4] = {0.3, 0.3, 0.3, 1};
#if TARGET_OS_IPHONE
static CGFloat kTransitionDuration = 0.3;
#endif
static CGFloat kPadding = 0;
static CGFloat kBorderWidth = 10;
static CGFloat kButtonPadding = 2;
static CGFloat kButtonWidth = 29;
static CGFloat kButtonHeight = 29;
#if TARGET_OS_MAC
static CGFloat kDialogWidth = 720;
static CGFloat kDialogHeight = 540;
#endif

///////////////////////////////////////////////////////////////////////////////////////////////////

#if TARGET_OS_IPHONE
static BOOL FBIsDeviceIPad() {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 30200
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        return YES;
    }
#endif
    return NO;
}
#endif

// This function determines if we want to use the legacy view layout in effect for iPhone OS 2.0
// through iOS 7, where we, the developer, have to worry about device orientation when working with
// views outside of the window's root view controller and apply the correct rotation transform and/
// or swap a view's width and height values. If the application was linked with UIKit on iOS 7 or
// earlier or the application is running on iOS 7 or earlier then we need to use the legacy layout
// code. Otherwise if the application was linked with UIKit on iOS 8 or later and the application
// is running on iOS 8 or later, UIKit handles all the rotation complexity and the origin is always
// in the top-left and no rotation transform is necessary.
#if TARGET_OS_IPHONE
static BOOL FBUseLegacyLayout(void) {
    return (![FBUtility isUIKitLinkedOnOrAfter:FBIOSVersion_8_0] ||
            ![FBUtility isRunningOnOrAfter:FBIOSVersion_8_0]);
}
#endif

///////////////////////////////////////////////////////////////////////////////////////////////////

@implementation FBDialog {
    BOOL _everShown;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// private

- (void)addRoundedRectToPath:(CGContextRef)context rect:(CGRect)rect radius:(float)radius {
    CGContextBeginPath(context);
    CGContextSaveGState(context);

    if (radius == 0) {
        CGContextTranslateCTM(context, CGRectGetMinX(rect), CGRectGetMinY(rect));
        CGContextAddRect(context, rect);
    } else {
        rect = CGRectOffset(CGRectInset(rect, 0.5, 0.5), 0.5, 0.5);
        CGContextTranslateCTM(context, CGRectGetMinX(rect)-0.5, CGRectGetMinY(rect)-0.5);
        CGContextScaleCTM(context, radius, radius);
        float fw = CGRectGetWidth(rect) / radius;
        float fh = CGRectGetHeight(rect) / radius;

        CGContextMoveToPoint(context, fw, fh/2);
        CGContextAddArcToPoint(context, fw, fh, fw/2, fh, 1);
        CGContextAddArcToPoint(context, 0, fh, 0, fh/2, 1);
        CGContextAddArcToPoint(context, 0, 0, fw/2, 0, 1);
        CGContextAddArcToPoint(context, fw, 0, fw, fh/2, 1);
    }

    CGContextClosePath(context);
    CGContextRestoreGState(context);
}

- (void)drawRect:(CGRect)rect fill:(const CGFloat *)fillColors radius:(CGFloat)radius {
#if TARGET_OS_IPHONE
    CGContextRef context = UIGraphicsGetCurrentContext();
#elif TARGET_OS_MAC
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
#endif
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();

    if (fillColors) {
        CGContextSaveGState(context);
        CGContextSetFillColor(context, fillColors);
        if (radius) {
            [self addRoundedRectToPath:context rect:rect radius:radius];
            CGContextFillPath(context);
        } else {
            CGContextFillRect(context, rect);
        }
        CGContextRestoreGState(context);
    }

    CGColorSpaceRelease(space);
}

- (void)strokeLines:(CGRect)rect stroke:(const CGFloat *)strokeColor {
#if TARGET_OS_IPHONE
    CGContextRef context = UIGraphicsGetCurrentContext();
#elif TARGET_OS_MAC
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
#endif
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();

    CGContextSaveGState(context);
    CGContextSetStrokeColorSpace(context, space);
    CGContextSetStrokeColor(context, strokeColor);
    CGContextSetLineWidth(context, 1.0);

    {
        CGPoint points[] = {{rect.origin.x+0.5, rect.origin.y-0.5},
            {rect.origin.x+rect.size.width, rect.origin.y-0.5}};
        CGContextStrokeLineSegments(context, points, 2);
    }
    {
        CGPoint points[] = {{rect.origin.x+0.5, rect.origin.y+rect.size.height-0.5},
            {rect.origin.x+rect.size.width-0.5, rect.origin.y+rect.size.height-0.5}};
        CGContextStrokeLineSegments(context, points, 2);
    }
    {
        CGPoint points[] = {{rect.origin.x+rect.size.width-0.5, rect.origin.y},
            {rect.origin.x+rect.size.width-0.5, rect.origin.y+rect.size.height}};
        CGContextStrokeLineSegments(context, points, 2);
    }
    {
        CGPoint points[] = {{rect.origin.x+0.5, rect.origin.y},
            {rect.origin.x+0.5, rect.origin.y+rect.size.height}};
        CGContextStrokeLineSegments(context, points, 2);
    }

    CGContextRestoreGState(context);

    CGColorSpaceRelease(space);
}

#if TARGET_OS_IPHONE
- (BOOL)shouldRotateToOrientation:(UIInterfaceOrientation)orientation {
    if (orientation == _orientation) {
        return NO;
    } else {
        return orientation == UIInterfaceOrientationPortrait
        || orientation == UIInterfaceOrientationPortraitUpsideDown
        || orientation == UIInterfaceOrientationLandscapeLeft
        || orientation == UIInterfaceOrientationLandscapeRight;
    }
}

- (CGAffineTransform)transformForOrientation {
    // iOS 8 simply adjusts the application frame to adapt to the current orientation and deprecated the concept of interface orientations
    if (FBUseLegacyLayout()) {
        UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
        if (orientation == UIInterfaceOrientationLandscapeLeft) {
            return CGAffineTransformMakeRotation(M_PI * 1.5);
        } else if (orientation == UIInterfaceOrientationLandscapeRight) {
            return CGAffineTransformMakeRotation(M_PI/2);
        } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
            return CGAffineTransformMakeRotation(-M_PI);
        }
    }

    return CGAffineTransformIdentity;
}

- (void)sizeToFitOrientation:(BOOL)transform {
    if (transform) {
        self.transform = CGAffineTransformIdentity;
    }

    CGRect frame = [UIScreen mainScreen].applicationFrame;
    CGPoint center = CGPointMake(
                                 frame.origin.x + ceil(frame.size.width/2),
                                 frame.origin.y + ceil(frame.size.height/2));

    CGFloat scale_factor = 1.0f;
    if (FBIsDeviceIPad()) {
        // On the iPad the dialog's dimensions should only be 60% of the screen's
        scale_factor = 0.6f;
    }

    CGFloat width = floor(scale_factor * frame.size.width) - kPadding * 2;
    CGFloat height = floor(scale_factor * frame.size.height) - kPadding * 2;

    _orientation = [UIApplication sharedApplication].statusBarOrientation;
    if (UIInterfaceOrientationIsPortrait(_orientation) || !FBUseLegacyLayout()) {
        self.frame = CGRectMake(kPadding, kPadding, width, height);
    } else {
        self.frame = CGRectMake(kPadding, kPadding, height, width);
    }
    self.center = center;

    if (transform) {
        self.transform = [self transformForOrientation];
    }
}

- (void)updateWebOrientation {
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    if (UIInterfaceOrientationIsLandscape(orientation)) {
        [_webView stringByEvaluatingJavaScriptFromString:
         @"document.body.setAttribute('orientation', 90);"];
    } else {
        [_webView stringByEvaluatingJavaScriptFromString:
         @"document.body.removeAttribute('orientation');"];
    }
}

- (void)bounce1AnimationStopped {
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:kTransitionDuration/2];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDidStopSelector:@selector(bounce2AnimationStopped)];
    self.transform = CGAffineTransformScale([self transformForOrientation], 0.9, 0.9);
    [UIView commitAnimations];
}

- (void)bounce2AnimationStopped {
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:kTransitionDuration/2];
    self.transform = [self transformForOrientation];
    [UIView commitAnimations];
}
#endif

- (NSURL *)generateURL:(NSString *)baseURL params:(NSDictionary *)params {
    if (params) {
        NSMutableArray *pairs = [NSMutableArray array];
        for (NSString *key in params.keyEnumerator) {
            id value = [params objectForKey:key];
            if ([value isKindOfClass:[NSNumber class]]) {
                value = [value stringValue];
            }
            if (![value isKindOfClass:[NSString class]]) {
                [FBLogger singleShotLogEntry:FBLoggingBehaviorDeveloperErrors formatString:@"%@ is not valid for generateURL", value];
                continue;
            }
            NSString *escaped_value = [FBUtility stringByURLEncodingString:value];
            [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, escaped_value]];
        }

        NSString *query = [pairs componentsJoinedByString:@"&"];
        NSString *url = [NSString stringWithFormat:@"%@?%@", baseURL, query];
        return [NSURL URLWithString:url];
    } else {
        return [NSURL URLWithString:baseURL];
    }
}

- (void)addObservers {
#if TARGET_OS_IPHONE
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(deviceOrientationDidChange:)
                                                 name:@"UIDeviceOrientationDidChangeNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:) name:@"UIKeyboardWillShowNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:) name:@"UIKeyboardWillHideNotification" object:nil];
#endif
}

- (void)removeObservers {
#if TARGET_OS_IPHONE
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:@"UIDeviceOrientationDidChangeNotification" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:@"UIKeyboardWillShowNotification" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:@"UIKeyboardWillHideNotification" object:nil];
#endif
}

- (void)postDismissCleanup {
    [self removeObservers];
#if TARGET_OS_IPHONE
    [self removeFromSuperview];
#elif TARGET_OS_MAC
    _webView.resourceLoadDelegate = nil;
    _webView.frameLoadDelegate = nil;
    [_closeButton setTarget:nil];
    [_closeButton setAction:nil];
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(webView:willPerformClientRedirectToURL:delay:fireDate:forFrame:)
                                               object:nil];
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(webView:didReceiveServerRedirectForProvisionalLoadForFrame:)
                                               object:nil];
#endif
    [_modalBackgroundView removeFromSuperview];

    // this method call could cause a self-cleanup, and needs to really happen "last"
    // If the dialog has been closed, then we need to cancel the order to open it.
    // This happens in the case of a frictionless request, see webViewDidFinishLoad for details
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(showWebView)
                                               object:nil];
}

- (void)dismiss:(BOOL)animated {
    [self dialogWillDisappear];

    [_loadingURL release];
    _loadingURL = nil;

#if TARGET_OS_IPHONE
    if (animated && _everShown) {
        [UIView beginAnimations:nil context:nil];
        [UIView setAnimationDuration:kTransitionDuration];
        [UIView setAnimationDelegate:self];
        [UIView setAnimationDidStopSelector:@selector(postDismissCleanup)];
        self.alpha = 0;
        [UIView commitAnimations];
    } else {
        [self postDismissCleanup];
    }
#elif TARGET_OS_MAC
    [self postDismissCleanup];
    [NSApp endSheet:_sheet];
#endif
}

- (void)cancel {
    [self dialogDidCancel:nil];
}

- (BOOL)testBoolUrlParam:(NSURL *)url param:(NSString *)param {
    NSString *paramVal = [self getStringFromUrl: [url absoluteString]
                                         needle: param];
    return [paramVal boolValue];
}

- (void)dialogSuccessHandleFrictionlessResponses:(NSURL *)url {
    // did we receive a recipient list?
    NSString *recipientJson = [self getStringFromUrl:[url absoluteString]
                                              needle:@"frictionless_recipients="];
    if (recipientJson) {
        // if value parses as an array, treat as set of fbids
        id recipients = [FBUtility simpleJSONDecode:recipientJson];

        // if we got something usable, copy the ids out and update the cache
        if ([recipients isKindOfClass:[NSArray class]]) {
            NSMutableArray *ids = [[[NSMutableArray alloc]
                                    initWithCapacity:[recipients count]]
                                   autorelease];
            for (id recipient in recipients) {
                NSString *fbid = [NSString stringWithFormat:@"%@", recipient];
                [ids addObject:fbid];
            }
            // we may be tempted to terminate outstanding requests before this
            // point, but that would cause problems if the user cancelled a dialog
            [_frictionlessSettings updateRecipientCacheWithRecipients:ids];
        }
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// NSObject

- (instancetype)init {
    if ((self = [super initWithFrame:CGRectZero])) {
        _delegate = nil;
        _loadingURL = nil;
        _showingKeyboard = NO;
        _everShown = NO;
#if TARGET_OS_MAC
        self.wantsLayer = YES;
        self.layer = [self makeBackingLayer];
        [self.layer setDelegate:self];
#endif

#if TARGET_OS_IPHONE
        self.backgroundColor = [UIColor clearColor];
        self.contentMode = UIViewContentModeRedraw;
#endif
        self.autoresizesSubviews = YES;
        self.autoresizingMask = FBFlexibleWidth | FBFlexibleHeight;

        _webView = [[FBWebView alloc] initWithFrame:CGRectMake(kBorderWidth, kBorderWidth, 640, 480)];
#if TARGET_OS_IPHONE
        _webView.delegate = self;
#elif TARGET_OS_MAC
        _webView.resourceLoadDelegate = self;
        _webView.frameLoadDelegate = self;
#endif
        _webView.autoresizingMask = FBFlexibleWidth | FBFlexibleHeight;
        [self addSubview:_webView];

#if TARGET_OS_IPHONE
        UIImage *closeImage = [FBDialogClosePNG image];
        UIColor *color = [UIColor colorWithRed:167.0/255 green:184.0/255 blue:216.0/255 alpha:1];
        _closeButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        [_closeButton setImage:closeImage forState:UIControlStateNormal];
        [_closeButton setTitleColor:color forState:UIControlStateNormal];
        [_closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
        [_closeButton addTarget:self action:@selector(cancel)
               forControlEvents:UIControlEventTouchUpInside];

        // To be compatible with OS 2.x
#if __IPHONE_OS_VERSION_MAX_ALLOWED <= __IPHONE_2_2
        _closeButton.font = [UIFont boldSystemFontOfSize:12];
#else
        _closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
#endif

        _closeButton.showsTouchWhenHighlighted = YES;
        _closeButton.autoresizingMask = UIViewAutoresizingFlexibleRightMargin
        | UIViewAutoresizingFlexibleBottomMargin;

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:
                    UIActivityIndicatorViewStyleWhiteLarge];
        if ([_spinner respondsToSelector:@selector(setColor:)]) {
            [_spinner setColor:[UIColor grayColor]];
        } else {
            [_spinner setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleGray];
        }
#elif TARGET_OS_MAC
        NSData* imageData = UIImagePNGRepresentation([FBDialogClosePNG image]);
        NSImage* closeImage = [[[NSImage alloc] initWithData:imageData] autorelease];
        _closeButton = [[[NSButton alloc] init] retain];
        [_closeButton setImage:closeImage];
        [_closeButton setImagePosition:NSImageOnly];
        [[_closeButton cell] setImageScaling:NSImageScaleProportionallyDown];
        [_closeButton setBordered:NO];
        
        [_closeButton setTarget:self];
        [_closeButton setAction:@selector(cancel)];
        [_closeButton setFont:[NSFont boldSystemFontOfSize:12]];
        [_closeButton setWantsLayer:YES];
        [_closeButton setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
        
        _spinner = [[NSProgressIndicator alloc] init];
        [_spinner setStyle:NSProgressIndicatorSpinningStyle];
#endif
        [_spinner setAutoresizingMask:FBFlexibleMargins];
        [self addSubview:_closeButton];
        [self addSubview:_spinner];
#if TARGET_OS_IPHONE
        _modalBackgroundView = [[UIView alloc] init];
#endif
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#if TARGET_OS_IPHONE
    _webView.delegate = nil;
#elif TARGET_OS_MAC
    _webView.resourceLoadDelegate = nil;
    _webView.frameLoadDelegate = nil;
    [_sheet release];
#endif
    [_webView release];
    [_params release];
    [_serverURL release];
    [_spinner release];
    [_closeButton release];
    [_loadingURL release];
    [_modalBackgroundView release];
    [_frictionlessSettings release];
    [super dealloc];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// UIView

- (void)drawRect:(CGRect)rect {
    [self drawRect:rect fill:kBorderGray radius:0];
    
    CGRect webRect = CGRectMake(
                                ceil(rect.origin.x + kBorderWidth), ceil(rect.origin.y + kBorderWidth)+1,
                                rect.size.width - kBorderWidth * 2, _webView.frame.size.height+1);

    [self strokeLines:webRect stroke:kBorderBlack];
}

#if TARGET_OS_MAC
- (void)didEndSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    [[sheet sheetParent] setDelegate:nil];
    [sheet orderOut:self];
}
#endif

// Display the dialog's WebView with a slick pop-up animation
- (void)showWebView {
    
#if TARGET_OS_IPHONE
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (window.windowLevel != UIWindowLevelNormal) {
        for(window in [UIApplication sharedApplication].windows) {
            if (window.windowLevel == UIWindowLevelNormal)
                break;
        }
    }
    _modalBackgroundView.frame = window.frame;
    [_modalBackgroundView addSubview:self];
    [window addSubview:_modalBackgroundView];

    self.transform = CGAffineTransformScale([self transformForOrientation], 0.001, 0.001);
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:kTransitionDuration/1.5];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDidStopSelector:@selector(bounce1AnimationStopped)];
    self.transform = CGAffineTransformScale([self transformForOrientation], 1.1, 1.1);
    [UIView commitAnimations];
#endif

    _everShown = YES;
    [self dialogWillAppear];
    [self addObservers];
#if TARGET_OS_MAC
    _sheet = [[NSWindow alloc] init];
    [_sheet setFrame:CGRectMake(kPadding, kPadding, kDialogWidth, kDialogHeight) display:YES];
    [_sheet setContentView:self];
    [_sheet setBackgroundColor:[NSColor clearColor]];
    FBWindow* window = [FBApplication sharedApplication].keyWindow;
    if (!window) {
        window = [[FBApplication sharedApplication].windows objectAtIndex:0];
    }
    
    [NSApp beginSheet:_sheet modalForWindow:window modalDelegate:self didEndSelector:@selector(didEndSheet:returnCode:contextInfo:) contextInfo:nil];
#endif
}

// Show a spinner during the loading time for the dialog. This is designed to show
// on top of the webview but before the contents have loaded.
- (void)showSpinner {
    [_spinner sizeToFit];
#if TARGET_OS_IPHONE
    [_spinner startAnimating];
    _spinner.center = _webView.center;
#elif TARGET_OS_MAC
    [_spinner startAnimation:self];
    NSRect spinnerFrame = [_spinner frame];
    NSRect selfBounds = [self bounds];
    NSPoint spinnerOrigin = NSMakePoint(ceil((NSWidth(selfBounds) - NSWidth(spinnerFrame)) / 2.0),
                                        ceil((NSHeight(selfBounds) - NSHeight(spinnerFrame)) / 2.0));
    [_spinner setFrameOrigin:spinnerOrigin];
#endif
}

- (void)hideSpinner {
#if TARGET_OS_IPHONE
    [_spinner stopAnimating];
#elif TARGET_OS_MAC
    [_spinner stopAnimation:self];
#endif
    _spinner.hidden = YES;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// UIWebViewDelegate

- (BOOL)checkURL:(NSURL*)url {
    if ([[url.resourceSpecifier substringToIndex:8] isEqualToString:@"//cancel"]) {
        NSString *errorCode = [self getStringFromUrl:[url absoluteString] needle:@"error_code="];
        NSString *errorStr = [self getStringFromUrl:[url absoluteString] needle:@"error_msg="];
        if (errorCode) {
            NSDictionary *errorData = [NSDictionary dictionaryWithObject:errorStr forKey:@"error_msg"];
            NSError *error = [NSError errorWithDomain:@"facebookErrDomain"
                                                 code:[errorCode intValue]
                                             userInfo:errorData];
            [self dismissWithError:error animated:YES];
        } else {
            [self dialogDidCancel:url];
        }
    } else {
        if (_frictionlessSettings.enabled) {
            [self dialogSuccessHandleFrictionlessResponses:url];
        }
        [self dialogDidSucceed:url];
    }
    return NO;
}

#if TARGET_OS_IPHONE
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request
 navigationType:(UIWebViewNavigationType)navigationType {
    NSURL *url = request.URL;

    if ([url.scheme isEqualToString:@"fbconnect"]) {
        return [self checkURL:url];
    } else if ([_loadingURL isEqual:url]) {
        return YES;
    } else if (navigationType == UIWebViewNavigationTypeLinkClicked) {
        if ([_delegate respondsToSelector:@selector(dialog:shouldOpenURLInExternalBrowser:)]) {
            if (![_delegate dialog:self shouldOpenURLInExternalBrowser:url]) {
                return NO;
            }
        }
        [FBAppCall openURL:request.URL];
        return NO;
    } else {
        return YES;
    }
}
#elif TARGET_OS_MAC
- (void)processRedirect:(WebView *)sender to:(NSURL*)url {
    BOOL proceed = YES;
    
    if ([url.relativeString hasPrefix:@"https://www.facebook.com/connect/login_success.html"]
        || [url.scheme isEqualToString:@"fbconnect"]) {
        proceed = [self checkURL:url];
    } else if ([_loadingURL isEqual:url]) {
        proceed = YES;
    } else if ([_delegate respondsToSelector:@selector(dialog:shouldOpenURLInExternalBrowser:)]) {
        if (![_delegate dialog:self shouldOpenURLInExternalBrowser:url]) {
            proceed = NO;
            [FBAppCall openURL:url];
        }
    }
    
    if(!proceed) {
        [sender stopLoading:sender];
    }
}
    
-(void)webView:(WebView *)sender willPerformClientRedirectToURL:(NSURL *)url delay:(NSTimeInterval)seconds fireDate:(NSDate *)date forFrame:(WebFrame *)frame {
    [self processRedirect:sender to:url];
}

- (void)webView:(FBWebView *)webView didReceiveServerRedirectForProvisionalLoadForFrame:(WebFrame *)frame {
    NSURL *url = [[[frame provisionalDataSource] request] URL];
    
    [self processRedirect:webView to:url];
}
#endif

#if TARGET_OS_IPHONE
- (void)webViewDidFinishLoad:(FBWebView *)webView {
#elif TARGET_OS_MAC
- (void)webView:(FBWebView *)webView resource:(id)identifier didFinishLoadingFromDataSource:(WebDataSource *)dataSource {
#endif
    if (_isViewInvisible) {
        // if our cache asks us to hide the view, then we do, but
        // in case of a stale cache, we will display the view in a moment
        // note that showing the view now would cause a visible white
        // flash in the common case where the cache is up to date
        [self performSelector:@selector(showWebView) withObject:nil afterDelay:.05];
    } else {
        [self hideSpinner];
    }
#if TARGET_OS_IPHONE
    [self updateWebOrientation];
#endif
}

#if TARGET_OS_IPHONE
- (void)webView:(FBWebView *)webView didFailLoadWithError:(NSError *)error {
#elif TARGET_OS_MAC
- (void)webView:(WebView *)webView resource:(id)identifier didFailLoadingWithError:(NSError *)error fromDataSource:(WebDataSource *)dataSource {
#endif
    // 102 == WebKitErrorFrameLoadInterruptedByPolicyChange
    // NSURLErrorCancelled == "Operation could not be completed", note NSURLErrorCancelled occurs when
    // the user clicks away before the page has completely loaded, if we find cases where we want this
    // to result in dialog failure (usually this just means quick-user), then we should add something
    // more robust here to account for differences in application needs
    if (!(([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) ||
          ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102))) {
        [self dismissWithError:error animated:YES];
    }
}

#if TARGET_OS_IPHONE
///////////////////////////////////////////////////////////////////////////////////////////////////
// UIDeviceOrientationDidChangeNotification

- (void)deviceOrientationDidChange:(void *)object {
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    if ([self shouldRotateToOrientation:orientation]) {
        [self updateWebOrientation];

        CGFloat duration = [UIApplication sharedApplication].statusBarOrientationAnimationDuration;
        [UIView beginAnimations:nil context:nil];
        [UIView setAnimationDuration:duration];
        [self sizeToFitOrientation:YES];
        [UIView commitAnimations];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// UIKeyboardNotifications

- (void)keyboardWillShow:(NSNotification *)notification {

    _showingKeyboard = YES;

    if (FBIsDeviceIPad()) {
        // On the iPad the screen is large enough that we don't need to
        // resize the dialog to accomodate the keyboard popping up
        return;
    }

    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    if (UIInterfaceOrientationIsLandscape(orientation)) {
        _webView.frame = CGRectInset(_webView.frame,
                                     - (kPadding + kBorderWidth),
                                     - (kPadding + kBorderWidth));
    }
}

- (void)keyboardWillHide:(NSNotification *)notification {
    _showingKeyboard = NO;

    if (FBIsDeviceIPad()) {
        return;
    }
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    if (UIInterfaceOrientationIsLandscape(orientation)) {
        _webView.frame = CGRectInset(_webView.frame,
                                     kPadding + kBorderWidth,
                                     kPadding + kBorderWidth);
    }
}
#endif

//////////////////////////////////////////////////////////////////////////////////////////////////
// public

/**
 * Find a specific parameter from the url
 */
- (NSString *)getStringFromUrl:(NSString *)url needle:(NSString *)needle {
    NSString *str = nil;
    NSRange start = [url rangeOfString:needle];
    if (start.location != NSNotFound) {
        // confirm that the parameter is not a partial name match
        unichar c = '?';
        if (start.location != 0) {
            c = [url characterAtIndex:start.location - 1];
        }
        if (c == '?' || c == '&' || c == '#') {
            NSRange end = [[url substringFromIndex:start.location+start.length] rangeOfString:@"&"];
            NSUInteger offset = start.location+start.length;
            str = end.location == NSNotFound ?
            [url substringFromIndex:offset] :
            [url substringWithRange:NSMakeRange(offset, end.location)];
            str = [str stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        }
    }
    return str;
}

- (id)      initWithURL:(NSString *)serverURL
                 params:(NSMutableDictionary *)params
        isViewInvisible:(BOOL)isViewInvisible
   frictionlessSettings:(FBFrictionlessRequestSettings *)frictionlessSettings
               delegate:(id<FBDialogDelegate>)delegate {

    self = [self init];
    _serverURL = [serverURL retain];
    _params = [params retain];
    _delegate = delegate;
    _isViewInvisible = isViewInvisible;
    _frictionlessSettings = [frictionlessSettings retain];

    return self;
}

- (void)load {
    [self loadURL:_serverURL get:_params];
}

- (void)loadURL:(NSString *)url get:(NSDictionary *)getParams {
    [_loadingURL release];
    _loadingURL = [[self generateURL:url params:getParams] retain];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:_loadingURL];

#if TARGET_OS_IPHONE
    [_webView loadRequest:request];
#elif TARGET_OS_MAC
    [[_webView mainFrame] loadRequest:request];
#endif
}

- (void)show {
    if ([FBSettings restrictedTreatment] == FBRestrictedTreatmentYES) {
        if ([_delegate respondsToSelector:@selector(dialog:didFailWithError:)]) {
            NSError *error = [NSError errorWithDomain:FacebookSDKDomain
                                                 code:FBErrorOperationDisallowedForRestrictedTreatment
                                             userInfo:nil];
            [_delegate dialog:self didFailWithError:error];
        }
        return;
    }
    [self load];
#if TARGET_OS_IPHONE
    [self sizeToFitOrientation:NO];
#endif
    if (!_isViewInvisible) {
        [self showSpinner];
        [self showWebView];
    }

    CGFloat innerWidth = NSWidth([self frame]) - (kBorderWidth + 1) * 2;
    CGFloat innerHeight = NSHeight([self frame]) - (kBorderWidth + 1) * 2;
    [_closeButton sizeToFit];

#if TARGET_OS_IPHONE
    _closeButton.frame = CGRectMake(kButtonPadding, kButtonPadding,
                                    kButtonWidth, kButtonHeight);
    
#elif TARGET_OS_MAC
    [_closeButton setFrameSize:NSMakeSize(kButtonWidth, kButtonHeight)];
    [_closeButton setFrameOrigin:NSMakePoint(kButtonPadding,
                                             NSHeight([self frame]) - kButtonHeight - kButtonPadding)];
#endif

    _webView.frame = CGRectMake(
                                kBorderWidth + 1,
                                kBorderWidth + 1,
                                innerWidth,
                                innerHeight);
}

- (void)dismissWithSuccess:(BOOL)success animated:(BOOL)animated {
    // retain self for the life of this method, in case we are released by a client
    id me = [self retain];

    @try {
        if (success) {
            if ([_delegate respondsToSelector:@selector(dialogDidComplete:)]) {
                [_delegate dialogDidComplete:self];
            }
        } else {
            if ([_delegate respondsToSelector:@selector(dialogDidNotComplete:)]) {
                [_delegate dialogDidNotComplete:self];
            }
        }

        [self dismiss:animated];
    } @finally {
        [me release];
    }
}

- (void)dismissWithError:(NSError *)error animated:(BOOL)animated {
    // retain self for the life of this method, in case we are released by a client
    id me = [self retain];

    @try {
        if ([_delegate respondsToSelector:@selector(dialog:didFailWithError:)]) {
            [_delegate dialog:self didFailWithError:error];
        }

        [self dismiss:animated];
    } @finally {
        [me release];
    }
}

- (void)dialogWillAppear {
}

- (void)dialogWillDisappear {
}

- (void)dialogDidSucceed:(NSURL *)url {
    // retain self for the life of this method, in case we are released by a client
    id me = [self retain];

    @try {
        // call into client code
        if ([_delegate respondsToSelector:@selector(dialogCompleteWithUrl:)]) {
            [_delegate dialogCompleteWithUrl:url];
        }

        [self dismissWithSuccess:YES animated:YES];
    } @finally {
        [me release];
    }
}

- (void)dialogDidCancel:(NSURL *)url {
    // retain self for the life of this method, in case we are released by a client
    id me = [self retain];

    @try {
        if ([_delegate respondsToSelector:@selector(dialogDidNotCompleteWithUrl:)]) {
            [_delegate dialogDidNotCompleteWithUrl:url];
        }
        [self dismissWithSuccess:NO animated:YES];
    } @finally {
        [me release];
    }
}

@end
