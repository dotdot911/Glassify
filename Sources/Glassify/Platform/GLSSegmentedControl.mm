//
//  GLSSegmentedControl.mm
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import "Glassify/GLSSegmentedControl.h"

#import "Glassify/GLSLiquidLensView.h"

#include <algorithm>
#include <cmath>
#include <vector>

namespace {
constexpr CGFloat kHeight = 32, kInset = 2, kLiftDX = 12, kLiftDY = 8, kSegmentPadding = 9, kFontSize = 13;
constexpr CGFloat kDamping = 0.85, kPositionResponse = 0.4, kTrackingResponse = 0.2;
constexpr CGFloat kHighlightAlpha = 0.2, kHighlightResponse = 0.42;
// A tapped lens unlifts this long after lifting, while it is still flying.
constexpr CFTimeInterval kTapLiftTime = 0.1;
// The lens's hang time at its target before it unlifts.
constexpr CFTimeInterval kHangTime = 0.22;

CGFloat RubberBand(CGFloat d) {
    const CGFloat s = d < 0 ? -1 : 1;
    const CGFloat a = std::fabs(d);
    return s * 12 * (1 - 1 / (1 + 0.55 * a / 12));
}
}

@interface GLSSegment : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) UIImage *image;
@property (nonatomic) BOOL enabled;
// Zero means automatic.
@property (nonatomic) CGFloat width;
@property (nonatomic) CGSize contentOffset;
@end
@implementation GLSSegment
@end

@implementation GLSSegmentedControl {
    NSMutableArray<GLSSegment *> *_segments;
    // Per segment, a UILabel or a UIImageView.
    NSMutableArray<UIView *> *_labels;
    std::vector<CGRect> _segmentFrames;
    NSMutableDictionary<NSNumber *, NSDictionary *> *_titleAttributes;
    NSMutableArray<UIAccessibilityElement *> *_axElements;
    UIView *_labelsView;
    // Copies of the labels, shown inside the lifted lens.
    UIView *_liftedLabels;
    // The resting background, faded out while the lens is lifted.
    UIView *_pill;
    GLSLiquidLensView *_lens;
    NSInteger _highlighted;
    BOOL _draggingLens;
    CGFloat _dragOffset;
    CGFloat _targetX;
    // A tap is flying the lens to another segment.
    BOOL _flying;
    CADisplayLink *_link;
    // Erases the labels under the lifted lens, which shows its own copies.
    CAShapeLayer *_punchout;
}

- (instancetype)initWithItems:(NSArray *)items {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    [self commonInit];
    for (id item in items) [self insertItem:item atIndex:_segments.count];
    [self segmentsChanged];
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self commonInit];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    [self commonInit];
    NSArray *titles = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSArray.class, NSString.class, NSNull.class, nil]
                                            forKey:@"GLSSegmentedTitles"];
    NSArray *images = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSArray.class, UIImage.class, NSNull.class, nil]
                                            forKey:@"GLSSegmentedImages"];
    for (NSUInteger i = 0; i < titles.count; ++i) {
        id image = i < images.count ? images[i] : nil;
        [self insertItem:[image isKindOfClass:UIImage.class] ? image : titles[i] atIndex:i];
    }
    _momentary = [coder decodeBoolForKey:@"GLSSegmentedMomentary"];
    _apportionsSegmentWidthsByContent = [coder decodeBoolForKey:@"GLSSegmentedApportions"];
    _selectedSegmentTintColor = [coder decodeObjectOfClass:UIColor.class forKey:@"GLSSegmentedSelectedTintColor"];
    [self segmentsChanged];
    if ([coder containsValueForKey:@"GLSSegmentedSelected"])
        self.selectedSegmentIndex = [coder decodeIntegerForKey:@"GLSSegmentedSelected"];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [super encodeWithCoder:coder];
    NSMutableArray *titles = [NSMutableArray array], *images = [NSMutableArray array];
    for (GLSSegment *s in _segments) {
        [titles addObject:s.title ?: (id)NSNull.null];
        [images addObject:s.image ?: (id)NSNull.null];
    }
    [coder encodeObject:titles forKey:@"GLSSegmentedTitles"];
    [coder encodeObject:images forKey:@"GLSSegmentedImages"];
    [coder encodeBool:_momentary forKey:@"GLSSegmentedMomentary"];
    [coder encodeBool:_apportionsSegmentWidthsByContent forKey:@"GLSSegmentedApportions"];
    if (_selectedSegmentTintColor) [coder encodeObject:_selectedSegmentTintColor forKey:@"GLSSegmentedSelectedTintColor"];
    [coder encodeInteger:_selectedSegmentIndex forKey:@"GLSSegmentedSelected"];
}

- (void)commonInit {
    _segments = [NSMutableArray array];
    _labels = [NSMutableArray array];
    _titleAttributes = [NSMutableDictionary dictionary];
    _selectedSegmentIndex = UISegmentedControlNoSegment;
    _highlighted = -1;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    if (@available(iOS 13.0, *)) self.backgroundColor = UIColor.tertiarySystemFillColor;
    _pill = [UIView new];
    _pill.userInteractionEnabled = NO;
    _pill.backgroundColor = UIColor.whiteColor;
    _pill.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:_pill];
    _lens = [[GLSLiquidLensView alloc] initWithFrame:CGRectZero];
    _lens.style = GLSLiquidLensStyleLarge;
    _lens.userInteractionEnabled = NO;
    [self addSubview:_lens];
    _labelsView = [UIView new];
    _labelsView.userInteractionEnabled = NO;
    [self addSubview:_labelsView];
    _liftedLabels = [UIView new];
    _lens.liftedContentView = _liftedLabels;
    _punchout = [CAShapeLayer layer];
    _punchout.fillRule = kCAFillRuleEvenOdd;
    [self updateSelectionVisibility];
}

- (void)dealloc { [_link invalidate]; }

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    _lens.backdropSourceView = _backdropSourceView ?: self.superview;
}

- (void)setBackdropSourceView:(UIView *)view {
    _backdropSourceView = view;
    _lens.backdropSourceView = view ?: self.superview;
}

#pragma mark Segments

- (void)insertItem:(id)item atIndex:(NSUInteger)index {
    GLSSegment *s = [GLSSegment new];
    s.enabled = YES;
    if ([item isKindOfClass:UIImage.class]) s.image = item;
    else s.title = [item description];
    [_segments insertObject:s atIndex:index];
    [_labels insertObject:[self contentViewForSegment:s] atIndex:index];
}

- (UIView *)contentViewForSegment:(GLSSegment *)s {
    UIView *v;
    if (s.image) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:s.image];
        iv.contentMode = UIViewContentModeCenter;
        if (@available(iOS 13.0, *)) iv.tintColor = UIColor.labelColor;
        v = iv;
    } else {
        UILabel *l = [UILabel new];
        l.text = s.title;
        l.textAlignment = NSTextAlignmentCenter;
        v = l;
    }
    [_labelsView addSubview:v];
    return v;
}

- (void)replaceContentAtIndex:(NSUInteger)i {
    [_labels[i] removeFromSuperview];
    _labels[i] = [self contentViewForSegment:_segments[i]];
}

- (void)segmentsChanged {
    [self updateFonts];
    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout];
    [self updateSelectionVisibility];
    _axElements = nil;
}

- (NSArray *)items {
    NSMutableArray *items = [NSMutableArray array];
    for (GLSSegment *s in _segments) [items addObject:s.image ?: s.title ?: @""];
    return items;
}

- (void)setItems:(NSArray *)items {
    [self removeAllSegments];
    for (id item in items) [self insertItem:item atIndex:_segments.count];
    [self segmentsChanged];
}

- (NSUInteger)numberOfSegments { return _segments.count; }

- (void)insertSegmentWithTitle:(NSString *)title atIndex:(NSUInteger)index animated:(BOOL)animated {
    [self insertSegmentItem:title ?: @"" atIndex:index];
}

- (void)insertSegmentWithImage:(UIImage *)image atIndex:(NSUInteger)index animated:(BOOL)animated {
    [self insertSegmentItem:image ?: (id)@"" atIndex:index];
}

// The index is clamped to the end; a selection at or after it moves with its segment.
- (void)insertSegmentItem:(id)item atIndex:(NSUInteger)index {
    index = std::min<NSUInteger>(index, _segments.count);
    [self insertItem:item atIndex:index];
    if (_selectedSegmentIndex >= 0 && NSUInteger(_selectedSegmentIndex) >= index) ++_selectedSegmentIndex;
    [self segmentsChanged];
}

// UIKit leaves -2 when the selected segment is removed; this clears the selection instead.
- (void)removeSegmentAtIndex:(NSUInteger)index animated:(BOOL)animated {
    if (index >= _segments.count) return;
    [_labels[index] removeFromSuperview];
    [_labels removeObjectAtIndex:index];
    [_segments removeObjectAtIndex:index];
    if (_selectedSegmentIndex == NSInteger(index)) _selectedSegmentIndex = UISegmentedControlNoSegment;
    else if (_selectedSegmentIndex > NSInteger(index)) --_selectedSegmentIndex;
    [self segmentsChanged];
}

- (void)removeAllSegments {
    for (UIView *v in _labels) [v removeFromSuperview];
    [_labels removeAllObjects];
    [_segments removeAllObjects];
    _selectedSegmentIndex = UISegmentedControlNoSegment;
    [self segmentsChanged];
}

// Out-of-range indexes raise NSRangeException, as in UIKit.
- (void)setTitle:(NSString *)title forSegmentAtIndex:(NSUInteger)index {
    GLSSegment *s = _segments[index];
    s.title = title;
    s.image = nil;
    [self replaceContentAtIndex:index];
    [self segmentsChanged];
}

- (NSString *)titleForSegmentAtIndex:(NSUInteger)index { return _segments[index].title; }

- (void)setImage:(UIImage *)image forSegmentAtIndex:(NSUInteger)index {
    GLSSegment *s = _segments[index];
    s.image = image;
    if (image) s.title = nil;
    [self replaceContentAtIndex:index];
    [self segmentsChanged];
}

- (UIImage *)imageForSegmentAtIndex:(NSUInteger)index { return _segments[index].image; }

- (void)setEnabled:(BOOL)enabled forSegmentAtIndex:(NSUInteger)index {
    _segments[index].enabled = enabled;
    [self segmentsChanged];
}

- (BOOL)isEnabledForSegmentAtIndex:(NSUInteger)index { return _segments[index].enabled; }

- (void)setWidth:(CGFloat)width forSegmentAtIndex:(NSUInteger)index {
    _segments[index].width = std::max(width, CGFloat(0));
    [self segmentsChanged];
}

- (CGFloat)widthForSegmentAtIndex:(NSUInteger)index { return _segments[index].width; }

- (void)setContentOffset:(CGSize)offset forSegmentAtIndex:(NSUInteger)index {
    _segments[index].contentOffset = offset;
    [self setNeedsLayout];
}

- (CGSize)contentOffsetForSegmentAtIndex:(NSUInteger)index { return _segments[index].contentOffset; }

- (void)setApportionsSegmentWidthsByContent:(BOOL)apportions {
    _apportionsSegmentWidthsByContent = apportions;
    [self segmentsChanged];
}

- (void)setSelectedSegmentTintColor:(UIColor *)color {
    _selectedSegmentTintColor = color;
    _pill.backgroundColor = color ?: UIColor.whiteColor;
}

- (void)setTitleTextAttributes:(NSDictionary<NSAttributedStringKey, id> *)attributes forState:(UIControlState)state {
    _titleAttributes[@(state)] = [attributes copy];
    [self segmentsChanged];
}

- (NSDictionary<NSAttributedStringKey, id> *)titleTextAttributesForState:(UIControlState)state {
    return _titleAttributes[@(state)];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self updateFonts];
}

#pragma mark Content

- (UIFont *)fontSelected:(BOOL)selected {
    UIFont *f = _titleAttributes[@(selected ? UIControlStateSelected : UIControlStateNormal)][NSFontAttributeName];
    if (!f && selected) f = _titleAttributes[@(UIControlStateNormal)][NSFontAttributeName];
    return f ?: [UIFont systemFontOfSize:kFontSize weight:selected ? UIFontWeightMedium : UIFontWeightRegular];
}

- (void)updateFonts {
    for (NSUInteger i = 0; i < _labels.count; ++i) {
        const BOOL selected = NSInteger(i) == _selectedSegmentIndex;
        const BOOL enabled = self.enabled && _segments[i].enabled;
        UIControlState state = selected ? UIControlStateSelected : UIControlStateNormal;
        if (!enabled) state = UIControlStateDisabled;
        UIColor *color = _titleAttributes[@(state)][NSForegroundColorAttributeName]
                             ?: _titleAttributes[@(UIControlStateNormal)][NSForegroundColorAttributeName];
        if (!color) color = enabled ? UIColor.labelColor : UIColor.tertiaryLabelColor;
        if ([_labels[i] isKindOfClass:UILabel.class]) {
            UILabel *l = (UILabel *)_labels[i];
            l.font = [self fontSelected:selected];
            l.textColor = color;
        } else {
            _labels[i].tintColor = color;
        }
    }
    [self rebuildLiftedLabels];
}

- (void)rebuildLiftedLabels {
    for (UIView *v in _liftedLabels.subviews) [v removeFromSuperview];
    for (UIView *v in _labels) {
        UIView *copy;
        if ([v isKindOfClass:UILabel.class]) {
            UILabel *l = (UILabel *)v, *c = [UILabel new];
            c.text = l.text;
            c.font = l.font;
            c.textColor = l.textColor;
            c.textAlignment = NSTextAlignmentCenter;
            copy = c;
        } else {
            UIImageView *c = [[UIImageView alloc] initWithImage:((UIImageView *)v).image];
            c.contentMode = UIViewContentModeCenter;
            c.tintColor = v.tintColor;
            copy = c;
        }
        copy.frame = v.frame;
        [_liftedLabels addSubview:copy];
    }
    [_lens setNeedsContentUpdate];
}

#pragma mark Geometry

- (CGFloat)contentWidth:(NSUInteger)i {
    GLSSegment *s = _segments[i];
    if (s.image) return s.image.size.width;
    UIFont *font = [self fontSelected:YES];
    return std::ceil([s.title ?: @"" sizeWithAttributes:@{NSFontAttributeName : font}].width);
}

- (CGFloat)idealWidth:(NSUInteger)i {
    const CGFloat fixed = _segments[i].width;
    const CGFloat w = fixed > 0 ? fixed : [self contentWidth:i] + 2 * kSegmentPadding;
    return std::max(w, kHeight);
}

- (CGSize)intrinsicContentSize {
    const CGSize s = [self sizeThatFits:CGSizeZero];
    return CGSizeMake(_segments.count ? s.width : UIViewNoIntrinsicMetric, s.height - 1);
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGFloat fixed = 0, maxIdeal = 0, sumIdeal = 0;
    NSUInteger others = 0;
    for (NSUInteger i = 0; i < _segments.count; ++i) {
        if (!_apportionsSegmentWidthsByContent && _segments[i].width > 0) {
            fixed += _segments[i].width;
            continue;
        }
        const CGFloat ideal = [self idealWidth:i];
        maxIdeal = std::max(maxIdeal, ideal);
        sumIdeal += ideal;
        ++others;
    }
    const CGFloat w = _apportionsSegmentWidthsByContent ? sumIdeal : fixed + others * maxIdeal;
    return CGSizeMake(w, kHeight);
}

- (UIEdgeInsets)alignmentRectInsets { return UIEdgeInsetsMake(0, 0, 1, 0); }

// Fixed widths first; the others share the rest equally, or by content when apportioning.
- (void)computeSegmentFrames {
    const NSUInteger n = _segments.count;
    _segmentFrames.assign(n, CGRectZero);
    if (!n) return;
    const CGFloat height = self.bounds.size.height;
    std::vector<CGFloat> widths(n);
    CGFloat avail = self.bounds.size.width, sumIdeal = 0;
    NSUInteger others = n;
    for (NSUInteger i = 0; i < n; ++i) {
        const CGFloat fixed = _segments[i].width;
        if (fixed > 0) {
            avail -= fixed;
            --others;
            widths[i] = fixed;
        } else {
            widths[i] = [self idealWidth:i];
            sumIdeal += widths[i];
        }
    }
    const CGFloat scale = sumIdeal > 0 ? avail / sumIdeal : 0, equal = others ? avail / others : 0;
    CGFloat carry = 0;
    for (NSUInteger i = 0; i < n; ++i) {
        if (_segments[i].width > 0) continue;
        const BOOL last = i == n - 1;
        if (_apportionsSegmentWidthsByContent) {
            const CGFloat v = scale * widths[i];
            widths[i] = last ? std::ceil(v) : std::floor(v);
        } else {
            const CGFloat v = equal + carry;
            widths[i] = last ? std::ceil(v) : std::floor(v);
            carry = equal - widths[i];
        }
    }
    CGFloat x = 0;
    const BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    for (NSUInteger i = 0; i < n; ++i) {
        const CGFloat right = std::floor(x + widths[i]);
        CGRect r = CGRectMake(x, 0, right - x, height);
        if (rtl) r.origin.x = self.bounds.size.width - CGRectGetMaxX(r);
        _segmentFrames[i] = r;
        x = right;
    }
}

- (CGRect)segmentRect:(NSInteger)i {
    if (_segmentFrames.size() != _segments.count) [self computeSegmentFrames];
    if (i < 0 || NSUInteger(i) >= _segmentFrames.size()) return CGRectZero;
    return _segmentFrames[i];
}

- (CGRect)contentRect:(NSInteger)i {
    const CGSize o = _segments[i].contentOffset;
    return CGRectOffset([self segmentRect:i], o.width, o.height);
}

- (CGRect)restFrame:(NSInteger)i { return CGRectInset([self segmentRect:i], kInset, kInset); }

- (CGRect)liftedBounds {
    const CGRect r = [self restFrame:std::max<NSInteger>(_selectedSegmentIndex, 0)];
    return CGRectMake(0, 0, r.size.width + 2 * kLiftDX, r.size.height + 2 * kLiftDY);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.bounds.size.height / 2;
    [self computeSegmentFrames];
    _labelsView.frame = self.bounds;
    for (NSUInteger i = 0; i < _labels.count; ++i) _labels[i].frame = [self contentRect:i];
    _liftedLabels.frame = self.bounds;
    for (NSUInteger i = 0; i < _liftedLabels.subviews.count && i < _labels.count; ++i)
        _liftedLabels.subviews[i].frame = [self contentRect:i];
    _axElements = nil;
    _lens.liftedContentFrame = self.bounds;
    if (!_lens.lifted && !_draggingLens && _selectedSegmentIndex >= 0) {
        [UIView performWithoutAnimation:^{
            const CGRect r = [self restFrame:self->_selectedSegmentIndex];
            self->_lens.bounds = CGRectMake(0, 0, r.size.width, r.size.height);
            self->_lens.center = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
        }];
    }
    [self layoutPill];
}

// The resting pill follows the lens and fades out while it is lifted.
- (void)layoutPill {
    if (_selectedSegmentIndex < 0) return;
    const CGRect r = [self restFrame:_selectedSegmentIndex];
    CALayer *lens = _lens.layer.presentationLayer ?: _lens.layer;
    _pill.bounds = CGRectMake(0, 0, r.size.width, r.size.height);
    _pill.center = _link ? lens.position : _lens.center;
    _pill.layer.cornerRadius = r.size.height / 2;
}

#pragma mark Selection

- (void)setSelectedSegmentIndex:(NSInteger)index { [self setSelectedSegmentIndex:index animated:NO]; }

// Out-of-range indexes are ignored; NoSegment hides the selection.
- (void)setSelectedSegmentIndex:(NSInteger)index animated:(BOOL)animated {
    if (index < UISegmentedControlNoSegment || index >= NSInteger(_segments.count)) return;
    if (index == _selectedSegmentIndex && !animated) return;
    const BOOL wasNone = _selectedSegmentIndex < 0;
    _selectedSegmentIndex = index;
    [self updateFonts];
    [self updateSelectionVisibility];
    _axElements = nil;
    if (!animated || wasNone || index < 0) {
        [self setNeedsLayout];
        return;
    }
    [self flyLensToSelection];
}

- (void)updateSelectionVisibility {
    const BOOL none = _selectedSegmentIndex < 0;
    _pill.hidden = none;
    _lens.hidden = none;
}

// Lifts the lens, flies it to the selection and unlifts it after the hang time.
- (void)flyLensToSelection {
    _flying = !_lens.isLifted;
    [self liftLens:YES];
    const CGRect r = [self restFrame:_selectedSegmentIndex];
    _targetX = CGRectGetMidX(r);
    GLSAnimateWithSpring(kDamping, kPositionResponse, ^{
        self->_lens.center = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
    }, nil);
}

- (void)liftLens:(BOOL)lifted {
    if (lifted) [self startFrames];
    const CGRect rest = [self restFrame:_selectedSegmentIndex];
    const CGRect bounds = lifted ? [self liftedBounds] : CGRectMake(0, 0, rest.size.width, rest.size.height);
    [_lens setLifted:lifted animated:YES alongsideAnimations:^{
        self->_lens.bounds = bounds;
        self->_pill.alpha = lifted ? 0 : 1;
    }];
}

#pragma mark Frames

- (void)startFrames {
    if (_link) return;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(frameTick)];
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

// Runs while the lens moves: unlifts it at its target and keeps the pill and label mask in step.
- (void)frameTick {
    CALayer *lens = _lens.layer.presentationLayer ?: _lens.layer;
    const BOOL unlift = _flying ? _lens.liftedDuration >= kTapLiftTime
                                : std::fabs(_targetX - lens.position.x) < 8 && _lens.liftedDuration >= kHangTime;
    if (_lens.isLifted && !_draggingLens && unlift) {
        _flying = NO;
        [self liftLens:NO];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    const CGRect rest = [self restFrame:_selectedSegmentIndex];
    _pill.bounds = CGRectMake(0, 0, rest.size.width, rest.size.height);
    _pill.center = lens.position;
    const CGFloat a = _lens.liftAlpha;
    if (a > 0) {
        const CGRect r = [lens convertRect:lens.bounds toLayer:_labelsView.layer];
        UIBezierPath *path = [UIBezierPath bezierPathWithRect:CGRectInset(_labelsView.bounds, -50, -50)];
        [path appendPath:[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:std::min(r.size.width, r.size.height) / 2]];
        _punchout.frame = _labelsView.bounds;
        _punchout.path = path.CGPath;
        _punchout.opacity = 1;
        CALayer *mask = [CALayer layer];
        mask.frame = _labelsView.bounds;
        CAShapeLayer *full = [CAShapeLayer layer];
        full.frame = mask.bounds;
        full.path = [UIBezierPath bezierPathWithRect:CGRectInset(_labelsView.bounds, -50, -50)].CGPath;
        full.opacity = float(1 - a);
        [mask addSublayer:full];
        [mask addSublayer:_punchout];
        _labelsView.layer.mask = mask;
    } else {
        _labelsView.layer.mask = nil;
    }
    [CATransaction commit];
    [_lens setNeedsBackdropUpdate];
    if (!_lens.isLifted && !_draggingLens && _lens.liftProgress <= 0 && std::fabs(lens.position.x - _lens.center.x) < 0.25) {
        [_link invalidate];
        _link = nil;
        _labelsView.layer.mask = nil;
    }
}

- (void)setHighlightedSegment:(NSInteger)i {
    if (i == _highlighted) return;
    const NSInteger old = _highlighted;
    _highlighted = i;
    GLSAnimateWithSpring(1, kHighlightResponse, ^{
        if (old >= 0 && old < NSInteger(self->_labels.count)) self->_labels[old].alpha = 1;
        if (i >= 0) self->_labels[i].alpha = kHighlightAlpha;
    }, nil);
}

- (NSInteger)segmentAt:(CGPoint)p {
    if (!_segments.count) return -1;
    for (NSUInteger i = 0; i < _segments.count; ++i) {
        const CGRect r = [self segmentRect:i];
        if (p.x >= CGRectGetMinX(r) && p.x < CGRectGetMaxX(r)) return i;
    }
    const BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    return (p.x < CGRectGetMidX(self.bounds)) != rtl ? 0 : NSInteger(_segments.count) - 1;
}

#pragma mark Touches

- (BOOL)segmentEnabled:(NSInteger)i { return i >= 0 && NSUInteger(i) < _segments.count && _segments[i].enabled; }

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    const CGPoint p = [touch locationInView:self];
    const NSInteger i = [self segmentAt:p];
    if (i < 0) return NO;
    if (i == _selectedSegmentIndex && !_momentary) {
        _draggingLens = YES;
        _dragOffset = p.x - _lens.center.x;
        [self liftLens:YES];
    } else {
        [self setHighlightedSegment:[self segmentEnabled:i] ? i : -1];
    }
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    const CGPoint p = [touch locationInView:self];
    if (_draggingLens) {
        const CGFloat a = CGRectGetMidX([self restFrame:0]);
        const CGFloat b = CGRectGetMidX([self restFrame:NSInteger(_segments.count) - 1]);
        const CGFloat lo = std::min(a, b), hi = std::max(a, b);
        CGFloat x = p.x - _dragOffset;
        if (x < lo) x = lo + RubberBand(x - lo);
        if (x > hi) x = hi + RubberBand(x - hi);
        _targetX = x;
        GLSAnimateWithSpring(kDamping, kTrackingResponse, ^{
            self->_lens.center = CGPointMake(x, self->_lens.center.y);
        }, nil);
    } else {
        const NSInteger i = CGRectContainsPoint(CGRectInset(self.bounds, -20, -20), p) ? [self segmentAt:p] : -1;
        [self setHighlightedSegment:[self segmentEnabled:i] ? i : -1];
    }
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    const CGPoint p = [touch locationInView:self];
    NSInteger target = _selectedSegmentIndex;
    if (_draggingLens) {
        const NSInteger under = [self segmentAt:CGPointMake(_lens.center.x, 0)];
        if ([self segmentEnabled:under]) target = under;
        _draggingLens = NO;
    } else if (_highlighted >= 0 && CGRectContainsPoint(CGRectInset(self.bounds, -20, -20), p)) {
        target = _highlighted;
    }
    [self setHighlightedSegment:-1];
    const BOOL changed = target != _selectedSegmentIndex || (_momentary && target >= 0);
    const BOOL wasNone = _selectedSegmentIndex < 0;
    _selectedSegmentIndex = target;
    [self updateFonts];
    [self updateSelectionVisibility];
    _axElements = nil;
    if (wasNone || _momentary) [self setNeedsLayout];
    else [self flyLensToSelection];
    if (changed) [self sendActionsForControlEvents:UIControlEventValueChanged | UIControlEventPrimaryActionTriggered];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    _draggingLens = NO;
    [self setHighlightedSegment:-1];
    if (_selectedSegmentIndex >= 0) [self flyLensToSelection];
}

#pragma mark Accessibility

// The segments are the accessibility elements, one each.
- (BOOL)isAccessibilityElement { return NO; }

- (NSArray *)accessibilityElements {
    if (_axElements) return _axElements;
    _axElements = [NSMutableArray array];
    for (NSUInteger i = 0; i < _segments.count; ++i) {
        UIAccessibilityElement *e = [[UIAccessibilityElement alloc] initWithAccessibilityContainer:self];
        GLSSegment *s = _segments[i];
        e.accessibilityLabel = s.title ?: s.image.accessibilityLabel;
        UIAccessibilityTraits t = UIAccessibilityTraitButton;
        if (NSInteger(i) == _selectedSegmentIndex && !_momentary) t |= UIAccessibilityTraitSelected;
        if (!s.enabled || !self.enabled) t |= UIAccessibilityTraitNotEnabled;
        e.accessibilityTraits = t;
        e.accessibilityFrameInContainerSpace = [self segmentRect:i];
        [_axElements addObject:e];
    }
    return _axElements;
}

- (NSInteger)accessibilityElementCount { return self.accessibilityElements.count; }
- (id)accessibilityElementAtIndex:(NSInteger)index { return self.accessibilityElements[index]; }
- (NSInteger)indexOfAccessibilityElement:(id)element { return [self.accessibilityElements indexOfObject:element]; }

// The XCUIElementType UI tests see; an informal method of the accessibility runtime.
- (NSUInteger)_accessibilityAutomationType { return 37; }

@end
