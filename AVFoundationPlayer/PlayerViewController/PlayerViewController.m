/**
 * Copyright © 2017-present Naeem Shaikh
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "PlayerViewController.h"

// Private Properties
@interface PlayerViewController ()
{
    AVQueuePlayer *_player;
    
    /*
     A token obtained from calling `player`'s `addPeriodicTimeObserverForInterval(_:queue:usingBlock:)`
     method.
     */
    id<NSObject> _timeObserverToken;
}

@property NSMutableDictionary *assetTitlesAndThumbnailsByURL;

@property (weak, nonatomic) IBOutlet UIButton *playPauseButton;
@property (weak, nonatomic) IBOutlet UISlider *timeSlider;
@property (weak, nonatomic) IBOutlet PlayerView *playerView;
@end

@implementation PlayerViewController

/*
	KVO context used to differentiate KVO callbacks for this class versus other
	classes in its class hierarchy.
*/
static int PlayerViewControllerKVOContext = 0;

+ (NSString *)identifier {
    return @"playerViewController";
}

#pragma mark - View Controller

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    /*
     Update the UI when these player properties change.
     
     Use the context parameter to distinguish KVO for our particular observers and not
     those destined for a subclass that also happens to be observing these properties.
     */
    [self addObserver:self forKeyPath:@"player.currentItem.duration" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial context:&PlayerViewControllerKVOContext];
    [self addObserver:self forKeyPath:@"player.rate" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial context:&PlayerViewControllerKVOContext];
    [self addObserver:self forKeyPath:@"player.currentItem.status" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial context:&PlayerViewControllerKVOContext];
    
    self.playerView.playerLayer.player = self.player;
    
    // Use a weak self variable to avoid a retain cycle in the block.
    PlayerViewController __weak *weakSelf = self;
    _timeObserverToken = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 1) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        double timeElapsed = CMTimeGetSeconds(time);
        weakSelf.timeSlider.value = timeElapsed;
    }];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
    if (_timeObserverToken) {
        [self.player removeTimeObserver:_timeObserverToken];
        _timeObserverToken = nil;
    }
    
    [self.player pause];
    
    // Remove Observers
    [self removeObserver:self forKeyPath:@"player.currentItem.duration" context:&PlayerViewControllerKVOContext];
    [self removeObserver:self forKeyPath:@"player.rate" context:&PlayerViewControllerKVOContext];
    [self removeObserver:self forKeyPath:@"player.currentItem.status" context:&PlayerViewControllerKVOContext];
}

#pragma mark - Properties

// Will attempt load and test these asset keys before playing
+ (NSArray *)assetKeysRequiredToPlay {
    return @[@"playable", @"hasProtectedContent"];
}

- (AVQueuePlayer *)player {
    if (!_player) {
        _player = [[AVQueuePlayer alloc] init];
    }
    return _player;
}

- (CMTime)currentTime {
    return self.player.currentTime;
}

- (void)setCurrentTime:(CMTime)newCurrentTime {
    [self.player seekToTime:newCurrentTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

- (CMTime)duration {
    return self.player.currentItem ? self.player.currentItem.duration : kCMTimeZero;
}

- (AVPlayerLayer *)playerLayer {
    return self.playerView.playerLayer;
}

#pragma mark - Asset Loading

/*
 Prepare an AVAsset for use on a background thread. When the minimum set
 of properties we require (`assetKeysRequiredToPlay`) are loaded then add
 the asset to the `assetTitlesAndThumbnails` dictionary. We'll use that
 dictionary to play videos.
 */
- (void)asynchronouslyLoadURLAsset:(AVURLAsset *)asset thumbnailURL:(NSString *)thumbnailURLString {
    
    NSString *title = @"video";
    /*
     Using AVAsset now runs the risk of blocking the current thread (the
     main UI thread) whilst I/O happens to populate the properties. It's
     prudent to defer our work until the properties we need have been loaded.
     */
    [asset loadValuesAsynchronouslyForKeys:PlayerViewController.assetKeysRequiredToPlay completionHandler:^{
        
        /*
         The asset invokes its completion handler on an arbitrary queue.
         To avoid multiple threads using our internal state at the same time
         we'll elect to use the main thread at all times, let's dispatch
         our handler to the main queue.
         */
        dispatch_async(dispatch_get_main_queue(), ^{
            
            /*
             This method is called when the `AVAsset` for our URL has
             completed the loading of the values of the specified array
             of keys.
             */
            
            /*
             Test whether the values of each of the keys we need have been
             successfully loaded.
             */
            for (NSString *key in self.class.assetKeysRequiredToPlay) {
                NSError *error = nil;
                if ([asset statusOfValueForKey:key error:&error] == AVKeyValueStatusFailed) {
                    NSString *stringFormat = NSLocalizedString(@"error.asset_%@_key_%@_failed.description", @"Can't use this AVAsset because one of it's keys failed to load");
                    
                    NSString *message = [NSString localizedStringWithFormat:stringFormat, title, key];
                    
                    [self handleErrorWithMessage:message error:error];
                    
                    return;
                }
            }
            
            // We can't play this asset.
            if (!asset.playable || asset.hasProtectedContent) {
                NSString *stringFormat = NSLocalizedString(@"error.asset_%@_not_playable.description", @"Can't use this AVAsset because it isn't playable or has protected content");
                
                NSString *message = [NSString localizedStringWithFormat:stringFormat, title];
                
                [self handleErrorWithMessage:message error:nil];
                
                return;
            }
            
            /*
             We can play this asset. Create a new AVPlayerItem and make it
             our player's current item.
             */
            if (!self.loadedAssets) {
                self.loadedAssets = [NSMutableDictionary dictionary];
            }
            self.loadedAssets[title] = asset;
            
            if (!self.assetTitlesAndThumbnailsByURL) {
                self.assetTitlesAndThumbnailsByURL = [NSMutableDictionary dictionary];
            }
            self.assetTitlesAndThumbnailsByURL[asset.URL] = @{ @"title" : title, @"thumbnail" : thumbnailURLString };
            
            AVAsset *loadedAsset = self.loadedAssets[title];
            AVPlayerItem *newPlayerItem = [AVPlayerItem playerItemWithAsset:loadedAsset];
            [self.player insertItem:newPlayerItem afterItem:nil];
            
        });
    }];
}

#pragma mark - IBAction
- (IBAction)playPauseButtonWasPressed:(UIButton *)sender {
    if (self.player.rate != 1.0) {
        // Not playing foward; so play.
        if (CMTIME_COMPARE_INLINE(self.currentTime, ==, self.duration)) {
            // At end; so got back to beginning.
            self.currentTime = kCMTimeZero;
        }
        [self.player play];
    }
    else {
        // Playing; so pause.
        [self.player pause];
    }
}

- (IBAction)timeSliderDidChanged:(UISlider *)sender {
    self.currentTime = CMTimeMakeWithSeconds(sender.value, 1000);
}

#pragma mark - KV Observation

// Update our UI when player or player.currentItem changes
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    
    if (context != &PlayerViewControllerKVOContext) {
        // KVO isn't for us.
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    
    if ([keyPath isEqualToString:@"player.currentItem.duration"]) {
        // Update timeSlider and enable/disable controls when duration > 0.0
        
        // Handle NSNull value for NSKeyValueChangeNewKey, i.e. when player.currentItem is nil
        NSValue *newDurationAsValue = change[NSKeyValueChangeNewKey];
        CMTime newDuration = [newDurationAsValue isKindOfClass:[NSValue class]] ? newDurationAsValue.CMTimeValue : kCMTimeZero;
        BOOL hasValidDuration = CMTIME_IS_NUMERIC(newDuration) && newDuration.value != 0;
        double currentTime = hasValidDuration ? CMTimeGetSeconds(self.currentTime) : 0.0;
        double newDurationSeconds = hasValidDuration ? CMTimeGetSeconds(newDuration) : 0.0;
        
        self.timeSlider.maximumValue = newDurationSeconds;
        self.timeSlider.value = currentTime;
        self.playPauseButton.enabled = hasValidDuration;
        self.timeSlider.enabled = hasValidDuration;
    }
    else if ([keyPath isEqualToString:@"player.rate"]) {
        // Update playPauseButton image
        
        double newRate = [change[NSKeyValueChangeNewKey] doubleValue];
        UIImage *buttonImage = (newRate == 1.0) ? [UIImage imageNamed:@"PauseButton"] : [UIImage imageNamed:@"PlayButton"];
        [self.playPauseButton setImage:buttonImage forState:UIControlStateNormal];
    }
    else if ([keyPath isEqualToString:@"player.currentItem.status"]) {
        // Display an error if status becomes Failed
        
        // Handle NSNull value for NSKeyValueChangeNewKey, i.e. when player.currentItem is nil
        NSNumber *newStatusAsNumber = change[NSKeyValueChangeNewKey];
        AVPlayerItemStatus newStatus = [newStatusAsNumber isKindOfClass:[NSNumber class]] ? newStatusAsNumber.integerValue : AVPlayerItemStatusUnknown;
        
        if (newStatus == AVPlayerItemStatusFailed) {
            [self handleErrorWithMessage:self.player.currentItem.error.localizedDescription error:self.player.currentItem.error];
        }
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - Error Handling

- (void)handleErrorWithMessage:(NSString *)message error:(NSError *)error {
    NSLog(@"Error occurred with message: %@, error: %@.", message, error);
    
    NSString *alertTitle = NSLocalizedString(@"alert.error.title", @"Alert title for errors");
    NSString *defaultAlertMessage = NSLocalizedString(@"error.default.description", @"Default error message when no NSError provided");
    UIAlertController *controller = [UIAlertController alertControllerWithTitle:alertTitle message:message ?: defaultAlertMessage  preferredStyle:UIAlertControllerStyleAlert];
    
    NSString *alertActionTitle = NSLocalizedString(@"alert.error.actions.OK", @"OK on error alert");
    UIAlertAction *action = [UIAlertAction actionWithTitle:alertActionTitle style:UIAlertActionStyleDefault handler:nil];
    [controller addAction:action];
    
    [self presentViewController:controller animated:YES completion:nil];
}

@end
