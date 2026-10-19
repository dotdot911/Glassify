//
//  GLSNavigationController.mm
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import "Glassify/GLSNavigationController.h"

#import "Glassify/GLSNavigationBar.h"
#import "Glassify/GLSScrollEdgeEffectView.h"
#import "Glassify/GLSToolbar.h"

#import <objc/runtime.h>

#include <algorithm>
#include <cmath>

static constexpr CGFloat kBarHeight = 54, kPlatterRow = 44, kToolbarHeight = 48, kToolbarMargin = 28,
                         kToolbarSafeGap = 10;

static NSArray<NSString *> *ItemKeys() {
    static NSArray *keys = @[ @"title", @"titleView", @"leftBarButtonItems", @"rightBarButtonItems", @"leftBarButtonItem",
                              @"rightBarButtonItem", @"hidesBackButton", @"leftItemsSupplementBackButton" ];
    return keys;
}

static NSArray<NSString *> *BarButtonKeys() {
    static NSArray *keys = @[ @"image", @"title", @"enabled", @"hidden", @"customView", @"primaryAction", @"menu" ];
    return keys;
}

// UIKit's ...animated: item setters send no KVO; this wraps one so observers of `key` hear about it.
static void SendKVOAround(Class cls, SEL sel, NSString *key) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    typedef void (*F)(id, SEL, id, BOOL);
    F orig = (F)method_getImplementation(m);
    const char *types = method_getTypeEncoding(m);
    const BOOL objectArg = types && strchr(types, '@') != strrchr(types, '@');
    if (objectArg) {
        method_setImplementation(m, imp_implementationWithBlock(^(id me, id value, BOOL animated) {
            [me willChangeValueForKey:key];
            orig(me, sel, value, animated);
            [me didChangeValueForKey:key];
        }));
    } else {
        typedef void (*G)(id, SEL, BOOL, BOOL);
        G orig2 = (G)orig;
        method_setImplementation(m, imp_implementationWithBlock(^(id me, BOOL value, BOOL animated) {
            [me willChangeValueForKey:key];
            orig2(me, sel, value, animated);
            [me didChangeValueForKey:key];
        }));
    }
}

#pragma mark - Edge swipe

// Lets UIKit's pop gesture begin while the system navigation bar is hidden.
@interface GLSPopGestureDelegate : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UINavigationController *navigationController;
@property (nonatomic, weak) id<UIGestureRecognizerDelegate> original;
@end

@implementation GLSPopGestureDelegate
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    UINavigationController *nav = _navigationController;
    return nav.viewControllers.count > 1 && !nav.transitionCoordinator &&
           !nav.topViewController.navigationItem.hidesBackButton;
}
- (BOOL)respondsToSelector:(SEL)sel {
    return [super respondsToSelector:sel] || [_original respondsToSelector:sel];
}
- (id)forwardingTargetForSelector:(SEL)sel {
    return [_original respondsToSelector:sel] ? _original : [super forwardingTargetForSelector:sel];
}
@end

#pragma mark - Controller

@implementation GLSNavigationController {
    GLSNavigationBar *_bar;
    GLSToolbar *_toolbar;
    GLSScrollEdgeEffectView *_topEdge, *_bottomEdge;
    BOOL _glassBarHidden, _glassToolbarHidden, _configured;
    UIEdgeInsets _userAdditional, _barInsets;
    GLSPopGestureDelegate *_popDelegate;
    __weak UIViewController *_shown;
    UIViewController *_observedController;
    UINavigationItem *_observedItem;
    NSArray<UIBarButtonItem *> *_observedButtons;
    BOOL _updateScheduled, _reloadButtons;
    BOOL _inTransition;
}

static void *kItemContext = &kItemContext;

+ (void)initialize {
    if (self != GLSNavigationController.class) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class item = UINavigationItem.class;
        SendKVOAround(item, @selector(setLeftBarButtonItems:animated:), @"leftBarButtonItems");
        SendKVOAround(item, @selector(setRightBarButtonItems:animated:), @"rightBarButtonItems");
        SendKVOAround(item, @selector(setLeftBarButtonItem:animated:), @"leftBarButtonItems");
        SendKVOAround(item, @selector(setRightBarButtonItem:animated:), @"rightBarButtonItems");
        SendKVOAround(item, @selector(setHidesBackButton:animated:), @"hidesBackButton");
        SendKVOAround(UIViewController.class, @selector(setToolbarItems:animated:), @"toolbarItems");
    });
}

- (void)configure {
    if (_configured) return;
    _configured = YES;
    _glassToolbarHidden = YES;
}

- (instancetype)initWithNibName:(NSString *)nibName bundle:(NSBundle *)bundle {
    if ((self = [super initWithNibName:nibName bundle:bundle])) [self configure];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) [self configure];
    return self;
}

- (instancetype)initWithNavigationBarClass:(Class)navigationBarClass toolbarClass:(Class)toolbarClass {
    if ((self = [super initWithNavigationBarClass:navigationBarClass toolbarClass:toolbarClass])) [self configure];
    return self;
}

// Some iOS versions do not route this through initWithNibName:bundle:.
- (instancetype)initWithRootViewController:(UIViewController *)rootViewController {
    [self configure];
    return [super initWithRootViewController:rootViewController];
}

- (void)dealloc {
    [self stopObserving];
}

- (GLSNavigationBar *)glassNavigationBar {
    [self loadViewIfNeeded];
    return _bar;
}

- (GLSToolbar *)glassToolbar {
    [self loadViewIfNeeded];
    return _toolbar;
}

- (GLSNavigationBar *)makeBar {
    GLSNavigationBar *bar = [GLSNavigationBar new];
    bar.scrollEdgeEffect = _topEdge;
    __weak GLSNavigationController *weakSelf = self;
    bar.backHandler = ^{ [weakSelf popViewControllerAnimated:YES]; };
    return bar;
}

- (GLSToolbar *)makeToolbar {
    GLSToolbar *toolbar = [GLSToolbar new];
    toolbar.scrollEdgeEffect = _bottomEdge;
    return toolbar;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self configure];
    [super setNavigationBarHidden:YES animated:NO];
    [super setToolbarHidden:YES animated:NO];
    _topEdge = [GLSScrollEdgeEffectView new];
    _topEdge.edge = GLSScrollEdgeTop;
    _bottomEdge = [GLSScrollEdgeEffectView new];
    _bottomEdge.edge = GLSScrollEdgeBottom;
    _bottomEdge.barHeight = kToolbarHeight;
    [self.view addSubview:_topEdge];
    [self.view addSubview:_bottomEdge];
    _toolbar = [self makeToolbar];
    [self.view addSubview:_toolbar];
    _bar = [self makeBar];
    [self.view addSubview:_bar];
    if (UIGestureRecognizer *pop = self.interactivePopGestureRecognizer) {
        _popDelegate = [GLSPopGestureDelegate new];
        _popDelegate.navigationController = self;
        _popDelegate.original = pop.delegate;
        pop.delegate = _popDelegate;
    }
    [self showItemsOf:self.topViewController];
}

#pragma mark Bars hidden

- (BOOL)isNavigationBarHidden { return _glassBarHidden; }
- (void)setNavigationBarHidden:(BOOL)hidden { [self setNavigationBarHidden:hidden animated:NO]; }
- (void)setNavigationBarHidden:(BOOL)hidden animated:(BOOL)animated {
    [super setNavigationBarHidden:YES animated:NO];
    if (hidden == _glassBarHidden) return;
    _glassBarHidden = hidden;
    [self animateBarsVisibility:animated];
}

- (BOOL)isToolbarHidden { return _glassToolbarHidden; }
- (void)setToolbarHidden:(BOOL)hidden { [self setToolbarHidden:hidden animated:NO]; }
- (void)setToolbarHidden:(BOOL)hidden animated:(BOOL)animated {
    [self configure];
    [super setToolbarHidden:YES animated:NO];
    if (hidden == _glassToolbarHidden) return;
    _glassToolbarHidden = hidden;
    [self animateBarsVisibility:animated];
}

// UIKit slides the bars; this fades them.
- (void)animateBarsVisibility:(BOOL)animated {
    if (!self.isViewLoaded) return;
    [self.view setNeedsLayout];
    void (^apply)(void) = ^{
        [self.view layoutIfNeeded];
        [self updateBarAlpha];
    };
    if (animated) [UIView animateWithDuration:0.35 animations:apply];
    else apply();
}

// UIKit hides the toolbar of a page without toolbarItems.
- (BOOL)toolbarVisible { return [self toolbarVisibleFor:_toolbar]; }
- (BOOL)toolbarVisibleFor:(GLSToolbar *)toolbar { return !_glassToolbarHidden && toolbar.items.count > 0; }

- (void)updateBarAlpha {
    if (_inTransition) return;
    _bar.alpha = _topEdge.alpha = _glassBarHidden ? 0 : 1;
    _toolbar.alpha = _bottomEdge.alpha = [self toolbarVisible] ? 1 : 0;
    _bar.userInteractionEnabled = !_glassBarHidden;
    _toolbar.userInteractionEnabled = [self toolbarVisible];
    _topEdge.hidden = _glassBarHidden;
    _bottomEdge.hidden = ![self toolbarVisible];
}

#pragma mark Safe area and layout

- (void)setAdditionalSafeAreaInsets:(UIEdgeInsets)insets {
    _userAdditional = insets;
    [self applyAdditionalInsets];
}

- (void)applyAdditionalInsets {
    const UIEdgeInsets u = _userAdditional, b = _barInsets;
    [super setAdditionalSafeAreaInsets:UIEdgeInsetsMake(u.top + b.top, u.left + b.left, u.bottom + b.bottom, u.right + b.right)];
}

// Places the bars inside the app's safe area and keeps them above the pages UIKit re-adds.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *view = self.view;
    const CGSize size = view.bounds.size;
    const UIEdgeInsets safe = view.safeAreaInsets;
    const CGFloat baseTop = safe.top - _barInsets.top, baseBottom = safe.bottom - _barInsets.bottom;
    const CGFloat toolbarTop = size.height - kToolbarMargin - kToolbarHeight;
    UIEdgeInsets bars = UIEdgeInsetsZero;
    if (!_glassBarHidden) bars.top = kBarHeight;
    if ([self toolbarVisible]) bars.bottom = std::max(size.height - toolbarTop + kToolbarSafeGap - baseBottom, CGFloat(0));
    if (!UIEdgeInsetsEqualToEdgeInsets(bars, _barInsets)) {
        _barInsets = bars;
        [self applyAdditionalInsets];
    }
    const CGFloat barTop = baseTop;
    for (UIView *v in view.subviews)
        if ([v isKindOfClass:GLSNavigationBar.class]) v.frame = CGRectMake(0, barTop, size.width, kBarHeight);
        else if ([v isKindOfClass:GLSToolbar.class])
            v.frame = CGRectMake(kToolbarMargin, toolbarTop, size.width - 2 * kToolbarMargin, kToolbarHeight);
    _topEdge.barEdge = barTop + kPlatterRow;
    _bottomEdge.barEdge = toolbarTop;
    NSArray<UIView *> *order = @[ _topEdge, _bottomEdge ];
    for (UIView *v in order) [view bringSubviewToFront:v];
    for (UIView *v in view.subviews.copy)
        if ([v isKindOfClass:GLSToolbar.class]) [view bringSubviewToFront:v];
    for (UIView *v in view.subviews.copy)
        if ([v isKindOfClass:GLSNavigationBar.class]) [view bringSubviewToFront:v];
    [self updateBarAlpha];
}

#pragma mark Pages → bars

// The page's content scroll view, else its first visible scroll view, breadth first.
static UIScrollView *ContentScrollView(UIViewController *vc) {
    if (!vc.isViewLoaded) return nil;
    if (@available(iOS 15.0, *)) {
        if (UIScrollView *s = [vc contentScrollViewForEdge:NSDirectionalRectEdgeTop]) return s;
    }
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:vc.view];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([v isKindOfClass:UIScrollView.class] && !v.hidden) return (UIScrollView *)v;
        [queue addObjectsFromArray:v.subviews];
    }
    return nil;
}

static BOOL SameItems(NSArray *a, NSArray *b) {
    if (a.count != b.count) return NO;
    for (NSUInteger i = 0; i < a.count; ++i)
        if (a[i] != b[i]) return NO;
    return YES;
}

static NSArray<UIBarButtonItem *> *VisibleItems(NSArray<UIBarButtonItem *> *items) {
    if (@available(iOS 16.0, *)) {
        NSIndexSet *hidden = [items indexesOfObjectsPassingTest:^BOOL(UIBarButtonItem *i, NSUInteger, BOOL *) { return i.hidden; }];
        if (hidden.count) {
            NSMutableArray *visible = items.mutableCopy;
            [visible removeObjectsAtIndexes:hidden];
            return visible;
        }
    }
    return items ?: @[];
}

- (void)configureBar:(GLSNavigationBar *)bar toolbar:(GLSToolbar *)toolbar forController:(UIViewController *)vc
              reload:(BOOL)reload {
    UINavigationItem *item = vc.navigationItem;
    bar.title = item.title ?: vc.title;
    bar.titleView = item.titleView;
    NSArray *left = VisibleItems(item.leftBarButtonItems), *right = VisibleItems(item.rightBarButtonItems);
    if (reload || !SameItems(bar.leftItems ?: @[], left)) bar.leftItems = left;
    if (reload || !SameItems(bar.rightItems ?: @[], right)) bar.rightItems = right;
    const NSUInteger index = [self.viewControllers indexOfObjectIdenticalTo:vc];
    const BOOL back = index != NSNotFound && index > 0 && !item.hidesBackButton &&
                      (left.count == 0 || item.leftItemsSupplementBackButton);
    if (back != bar.showsBackButton) bar.showsBackButton = back;
    NSArray *tools = VisibleItems(vc.toolbarItems);
    if (reload || !SameItems(toolbar.items ?: @[], tools)) toolbar.items = tools;
    UIScrollView *scroll = ContentScrollView(vc);
    if (!_inTransition) {
        bar.backdropSourceView = toolbar.backdropSourceView = scroll ?: vc.view;
    }
    bar.scrollView = scroll;
    toolbar.scrollView = scroll;
}

- (void)showItemsOf:(UIViewController *)vc {
    if (!_bar) return;
    _shown = vc;
    [self observeController:vc];
    if (vc) [self configureBar:_bar toolbar:_toolbar forController:vc reload:NO];
}

#pragma mark Observation

- (void)stopObserving {
    for (NSString *k in ItemKeys()) [_observedItem removeObserver:self forKeyPath:k context:kItemContext];
    [_observedController removeObserver:self forKeyPath:@"title" context:kItemContext];
    [_observedController removeObserver:self forKeyPath:@"toolbarItems" context:kItemContext];
    for (UIBarButtonItem *b in _observedButtons)
        for (NSString *k in BarButtonKeys()) [b removeObserver:self forKeyPath:k context:kItemContext];
    _observedItem = nil;
    _observedController = nil;
    _observedButtons = nil;
}

- (void)observeController:(UIViewController *)vc {
    if (vc == _observedController) {
        [self observeButtons];
        return;
    }
    [self stopObserving];
    if (!vc) return;
    _observedController = vc;
    _observedItem = vc.navigationItem;
    for (NSString *k in ItemKeys()) [_observedItem addObserver:self forKeyPath:k options:0 context:kItemContext];
    [vc addObserver:self forKeyPath:@"title" options:0 context:kItemContext];
    [vc addObserver:self forKeyPath:@"toolbarItems" options:0 context:kItemContext];
    [self observeButtons];
}

// Item image / title / enabled / hidden changes rebuild the bars.
- (void)observeButtons {
    NSMutableArray<UIBarButtonItem *> *buttons = [NSMutableArray array];
    UINavigationItem *item = _observedItem;
    if (item.leftBarButtonItems) [buttons addObjectsFromArray:item.leftBarButtonItems];
    if (item.rightBarButtonItems) [buttons addObjectsFromArray:item.rightBarButtonItems];
    if (_observedController.toolbarItems) [buttons addObjectsFromArray:_observedController.toolbarItems];
    if (SameItems(buttons, _observedButtons ?: @[])) return;
    for (UIBarButtonItem *b in _observedButtons)
        for (NSString *k in BarButtonKeys()) [b removeObserver:self forKeyPath:k context:kItemContext];
    _observedButtons = buttons;
    for (UIBarButtonItem *b in buttons)
        for (NSString *k in BarButtonKeys()) [b addObserver:self forKeyPath:k options:0 context:kItemContext];
}

// Coalesces changes, since apps often set several properties in a row.
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context {
    if (context != kItemContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    const BOOL buttonChanged = [object isKindOfClass:UIBarButtonItem.class];
    if (_updateScheduled) {
        _reloadButtons |= buttonChanged;
        return;
    }
    _updateScheduled = YES;
    _reloadButtons = buttonChanged;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_updateScheduled = NO;
        UIViewController *vc = self->_shown;
        if (!vc || self->_inTransition) return;
        [self observeButtons];
        [self configureBar:self->_bar toolbar:self->_toolbar forController:vc reload:self->_reloadButtons];
        [self.view setNeedsLayout];
    });
}

#pragma mark Transitions

- (void)pushViewController:(UIViewController *)vc animated:(BOOL)animated {
    [super pushViewController:vc animated:animated];
    [self topDidChange];
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated {
    UIViewController *vc = [super popViewControllerAnimated:animated];
    [self topDidChange];
    return vc;
}

- (NSArray<UIViewController *> *)popToViewController:(UIViewController *)vc animated:(BOOL)animated {
    NSArray *popped = [super popToViewController:vc animated:animated];
    [self topDidChange];
    return popped;
}

- (NSArray<UIViewController *> *)popToRootViewControllerAnimated:(BOOL)animated {
    NSArray *popped = [super popToRootViewControllerAnimated:animated];
    [self topDidChange];
    return popped;
}

- (void)setViewControllers:(NSArray<UIViewController *> *)vcs animated:(BOOL)animated {
    [super setViewControllers:vcs animated:animated];
    [self topDidChange];
}

// The view holding the pages (UIKit's transition view): the bars' backdrop while both pages show.
- (UIView *)pagesContainerFor:(UIViewController *)vc {
    UIView *v = vc.view;
    while (v.superview && v.superview != self.view) v = v.superview;
    return v.superview == self.view ? v : nil;
}

// A plain push or pop fades on its own: alongside animations only land at the transition's end.
- (void)topDidChange {
    if (!_bar) return;
    UIViewController *to = self.topViewController;
    if (to == _shown && !_inTransition) {
        [self showItemsOf:to];
        return;
    }
    id<UIViewControllerTransitionCoordinator> coordinator = self.transitionCoordinator;
    if (!coordinator || !coordinator.isAnimated || _inTransition) {
        [self showItemsOf:to];
        [self.view setNeedsLayout];
        return;
    }
    UIViewController *from = _shown;
    _inTransition = YES;
    [self stopObserving];
    GLSNavigationBar *oldBar = _bar, *newBar = [self makeBar];
    GLSToolbar *oldToolbar = _toolbar, *newToolbar = [self makeToolbar];
    [self configureBar:newBar toolbar:newToolbar forController:to reload:NO];
    UIView *pages = [self pagesContainerFor:to] ?: [self pagesContainerFor:from];
    oldBar.backdropSourceView = oldToolbar.backdropSourceView = pages;
    newBar.backdropSourceView = newToolbar.backdropSourceView = pages;
    newBar.alpha = 0;
    newToolbar.alpha = 0;
    const BOOL toolbarVisible = [self toolbarVisibleFor:newToolbar];
    newBar.userInteractionEnabled = newToolbar.userInteractionEnabled = NO;
    oldBar.userInteractionEnabled = oldToolbar.userInteractionEnabled = NO;
    [self.view insertSubview:newToolbar aboveSubview:oldToolbar];
    [self.view insertSubview:newBar aboveSubview:oldBar];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    const CGFloat barAlpha = _glassBarHidden ? 0 : 1, toolbarAlpha = toolbarVisible ? 1 : 0;
    void (^fade)(void) = ^{
        oldBar.alpha = 0;
        oldToolbar.alpha = 0;
        newBar.alpha = barAlpha;
        newToolbar.alpha = toolbarAlpha;
    };
    if (!coordinator.isInteractive)
        [UIView animateWithDuration:coordinator.transitionDuration delay:0
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction
                         animations:fade completion:nil];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
        if (ctx.isInteractive) fade();
    }
        completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
            const BOOL cancelled = ctx.isCancelled;
            GLSNavigationBar *keepBar = cancelled ? oldBar : newBar;
            GLSToolbar *keepToolbar = cancelled ? oldToolbar : newToolbar;
            [(cancelled ? newBar : oldBar) removeFromSuperview];
            [(cancelled ? newToolbar : oldToolbar) removeFromSuperview];
            self->_bar = keepBar;
            self->_toolbar = keepToolbar;
            self->_inTransition = NO;
            self->_shown = nil;
            [self showItemsOf:self.topViewController];
            [self.view setNeedsLayout];
            [self.view layoutIfNeeded];
        }];
}

@end
