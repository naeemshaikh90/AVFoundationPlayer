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

#import "BaseViewController.h"
#import "PlayerViewController.h"
#import "PlayingListModel.h"

// Private Properties
@interface BaseViewController ()
{
    NSMutableArray *assetsModelArray;
}
@end

@implementation BaseViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    /*
     Read the list of videos we'll be using from a JSON file.
     */
    [self loadVideoURLWithJSONFile:[[NSBundle mainBundle] URLForResource:@"PlayingList" withExtension:@"json"]];

    [self setupPageViewController];
    
    [self addChildViewController:self.pageViewController];
    [self.view addSubview:self.pageViewController.view];
    [self.pageViewController didMoveToParentViewController:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Subscribe to the AVPlayerItem's DidPlayToEndTime notification.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidFinishPlaying:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
    // Remove Observer
    [[NSNotificationCenter defaultCenter] removeObserver:AVPlayerItemDidPlayToEndTimeNotification];
}

#pragma mark - Asset Loading

/*
 Read the video URLs and thumbnail resource names from a JSON file
 */
- (void)loadVideoURLWithJSONFile:(NSURL *)jsonURL {
    NSDictionary *assetsDict = nil;
    NSArray *assetsArray = nil;
    
    NSData *jsonData = [[NSData alloc] initWithContentsOfURL:jsonURL];
    if (jsonData) {
        assetsDict = (NSDictionary *)[NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:nil];
        assetsArray = assetsDict[@"videos"];
        if (!assetsArray) {
            NSLog(@"Failed to parse the videos from JSON file");
        }
    }
    else {
        NSLog(@"Failed to open the JSON file");
    }
    
    assetsModelArray = [[NSMutableArray alloc] init];
    for (NSDictionary *assetDict in assetsArray) {
        PlayingListModel *model = [[PlayingListModel alloc] init];
        model.videoURL = assetDict[@"videoURL"];
        model.imageURL = assetDict[@"imageURL"];
        [assetsModelArray addObject:model];
    }
}

#pragma mark - UIPageViewController

- (void)setupPageViewController {
    PlayerViewController *pageZero = [self rootViewControllerForPageIndex:0];
    if (pageZero != nil) {
        self.pageViewController = [[UIPageViewController alloc]
                                   initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll
                                   navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal
                                   options:nil];
        self.pageViewController.dataSource = self;
        
        [self.pageViewController setViewControllers:@[pageZero]
                                          direction:UIPageViewControllerNavigationDirectionForward
                                           animated:NO
                                         completion:NULL];
    }
}

- (UIViewController *)pageViewController:(UIPageViewController *)pvc viewControllerBeforeViewController:(PlayerViewController *)vc {
    NSUInteger index = vc.pageIndex;
    return [self rootViewControllerForPageIndex:(index - 1)];
}

- (UIViewController *)pageViewController:(UIPageViewController *)pvc viewControllerAfterViewController:(PlayerViewController *)vc {
    NSUInteger index = vc.pageIndex;
    return [self rootViewControllerForPageIndex:(index + 1)];
}

- (void)changePageToNext {
    [self changePage:UIPageViewControllerNavigationDirectionForward];
}

- (void)changePageToPrev {
    [self changePage:UIPageViewControllerNavigationDirectionReverse];
}

- (void)changePage:(UIPageViewControllerNavigationDirection)direction {
    NSUInteger pageIndex = ((PlayerViewController *) [_pageViewController.viewControllers objectAtIndex:0]).pageIndex;
    
    if (direction == UIPageViewControllerNavigationDirectionForward) {
        pageIndex++;
    }
    else {
        pageIndex--;
    }
    
    PlayerViewController *viewController = [self rootViewControllerForPageIndex:pageIndex];
    
    if (viewController == nil) {
        return;
    }
    
    [_pageViewController setViewControllers:@[viewController]
                                  direction:direction
                                   animated:YES
                                 completion:nil];
}

- (PlayerViewController *)rootViewControllerForPageIndex:(NSUInteger)pageIndex {
    if (pageIndex < [assetsModelArray count]) {
        UIStoryboard *mainStoryboard = [UIStoryboard storyboardWithName:@"Main" bundle:[NSBundle mainBundle]];
        PlayerViewController *playerVC = [mainStoryboard instantiateViewControllerWithIdentifier:[PlayerViewController identifier]];
        playerVC.pageIndex = pageIndex;
        
        PlayingListModel *model = assetsModelArray[pageIndex];
        NSURL *videoURL = nil;
        NSString *videoURLString = model.videoURL;
        NSString *thumbnailURLString = model.imageURL;
        
        if (videoURLString) {
            videoURL = [NSURL URLWithString:videoURLString];
        }
        
        [playerVC asynchronouslyLoadURLAsset:[AVURLAsset URLAssetWithURL:videoURL options:nil]
                                thumbnailURL:thumbnailURLString];
        return  playerVC;
    }
    else {
        return nil;
    }
}

#pragma mark - NSNotification Observation

- (void)itemDidFinishPlaying:(NSNotification *) notification {
    // Will be called when AVPlayer finishes playing playerItem
    
    // Set AutoPlay to YES
    [self changePageToNext];
}

@end
