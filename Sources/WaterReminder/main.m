#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <unistd.h>

static NSString * const kStartHour = @"startHour";
static NSString * const kEndHour = @"endHour";
static NSString * const kEndMinute = @"endMinute";
static NSString * const kLunchStartHour = @"lunchStartHour";
static NSString * const kLunchStartMinute = @"lunchStartMinute";
static NSString * const kLunchEndHour = @"lunchEndHour";
static NSString * const kLunchEndMinute = @"lunchEndMinute";
static NSString * const kReminderIntervalMinutes = @"reminderIntervalMinutes";
static NSString * const kDailyTargetMl = @"dailyTargetMl";
static NSString * const kCompletedTodayMl = @"completedTodayMl";
static NSString * const kLastResetDay = @"lastResetDay";
static NSString * const kDrinkRecords = @"drinkRecords";
static NSString * const kOnboardingComplete = @"onboardingComplete";
static const NSInteger kDailyTargetDefaultMl = 2000;
static const NSInteger kDailyTargetMaxMl = 5000;
static const NSInteger kReminderAmountMl = 250;

@class AppDelegate;
@class ReminderWindowController;
@class SummaryWindowController;
@class PhoneChargeWindowController;
@class OnboardingWindowController;

static NSColor *DTPrimaryTextColor(void) {
    return [NSColor colorWithCalibratedWhite:0.08 alpha:1.0];
}

static NSColor *DTSecondaryTextColor(void) {
    return [NSColor colorWithCalibratedWhite:0.28 alpha:1.0];
}

static void DTConfigureGlassWindow(NSWindow *window) {
    window.level = NSFloatingWindowLevel;
    window.opaque = NO;
    window.backgroundColor = NSColor.clearColor;
    window.hasShadow = NO;
    window.movableByWindowBackground = YES;
    window.releasedWhenClosed = NO;
}

static NSVisualEffectView *DTGlassPanel(NSRect frame, CGFloat radius) {
    NSVisualEffectView *view = [[NSVisualEffectView alloc] initWithFrame:frame];
    view.material = NSVisualEffectMaterialHUDWindow;
    view.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    view.state = NSVisualEffectStateActive;
    view.wantsLayer = YES;
    view.layer.cornerRadius = radius;
    view.layer.masksToBounds = YES;

    NSView *tint = [[NSView alloc] initWithFrame:view.bounds];
    tint.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    tint.wantsLayer = YES;
    tint.layer.backgroundColor = [NSColor colorWithCalibratedWhite:1 alpha:0.72].CGColor;
    tint.layer.cornerRadius = radius;
    [view addSubview:tint positioned:NSWindowBelow relativeTo:nil];

    NSView *highlight = [[NSView alloc] initWithFrame:NSInsetRect(view.bounds, 1, 1)];
    highlight.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    highlight.wantsLayer = YES;
    highlight.layer.backgroundColor = [NSColor colorWithCalibratedWhite:1 alpha:0.10].CGColor;
    highlight.layer.cornerRadius = MAX(0, radius - 1);
    [view addSubview:highlight positioned:NSWindowBelow relativeTo:nil];
    return view;
}

@interface WaterModel : NSObject
@property (nonatomic) NSInteger startHour;
@property (nonatomic) NSInteger endHour;
@property (nonatomic) NSInteger endMinute;
@property (nonatomic) NSInteger lunchStartHour;
@property (nonatomic) NSInteger lunchStartMinute;
@property (nonatomic) NSInteger lunchEndHour;
@property (nonatomic) NSInteger lunchEndMinute;
@property (nonatomic) NSInteger reminderIntervalMinutes;
@property (nonatomic) NSInteger dailyTargetMl;
@property (nonatomic) NSInteger completedTodayMl;
@property (nonatomic) NSInteger reminderAmountMl;
- (void)resetIfNeeded;
- (void)completeCurrentReminder;
- (void)recordDrinkAmount:(NSInteger)amount;
- (void)updateWorkStartHour:(NSInteger)startHour endHour:(NSInteger)endHour endMinute:(NSInteger)endMinute;
- (void)updateLunchStartHour:(NSInteger)startHour startMinute:(NSInteger)startMinute endHour:(NSInteger)endHour endMinute:(NSInteger)endMinute;
- (void)updateReminderIntervalMinutes:(NSInteger)minutes;
- (void)updateDailyTargetMl:(NSInteger)targetMl;
- (void)setTodayTotalByManualAdjustment:(NSInteger)targetMl;
- (NSArray<NSDictionary *> *)dailyTotalsForLastDays:(NSInteger)dayCount;
- (NSArray<NSDictionary *> *)hourlyTotalsForToday;
- (NSDate *)nextReminderDate;
- (NSString *)nextReminderText;
- (double)progress;
@end

@implementation WaterModel

- (instancetype)init {
    self = [super init];
    if (!self) { return nil; }

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    self.startHour = [defaults objectForKey:kStartHour] ? [defaults integerForKey:kStartHour] : 9;
    self.endHour = [defaults objectForKey:kEndHour] ? [defaults integerForKey:kEndHour] : 17;
    self.endMinute = [defaults objectForKey:kEndMinute] ? [defaults integerForKey:kEndMinute] : 30;
    self.lunchStartHour = [defaults objectForKey:kLunchStartHour] ? [defaults integerForKey:kLunchStartHour] : 11;
    self.lunchStartMinute = [defaults objectForKey:kLunchStartMinute] ? [defaults integerForKey:kLunchStartMinute] : 30;
    self.lunchEndHour = [defaults objectForKey:kLunchEndHour] ? [defaults integerForKey:kLunchEndHour] : 13;
    self.lunchEndMinute = [defaults objectForKey:kLunchEndMinute] ? [defaults integerForKey:kLunchEndMinute] : 30;
    self.reminderIntervalMinutes = [defaults objectForKey:kReminderIntervalMinutes] ? [defaults integerForKey:kReminderIntervalMinutes] : 60;
    self.dailyTargetMl = [defaults objectForKey:kDailyTargetMl] ? [defaults integerForKey:kDailyTargetMl] : kDailyTargetDefaultMl;
    if (![defaults boolForKey:kOnboardingComplete]) {
        self.startHour = 9;
        self.endHour = 17;
        self.endMinute = 30;
    }
    NSInteger legacyCompleted = [defaults objectForKey:kCompletedTodayMl] ? [defaults integerForKey:kCompletedTodayMl] : 0;
    if (![defaults objectForKey:kDrinkRecords] && legacyCompleted > 0) {
        [self appendDrinkRecordWithAmount:legacyCompleted kind:@"legacy"];
    }
    [self resetIfNeeded];
    [self recompute];
    return self;
}

- (void)setStartHour:(NSInteger)startHour {
    _startHour = startHour;
    [NSUserDefaults.standardUserDefaults setInteger:startHour forKey:kStartHour];
    [NSUserDefaults.standardUserDefaults synchronize];
    [self recompute];
}

- (void)setEndHour:(NSInteger)endHour {
    _endHour = endHour;
    [NSUserDefaults.standardUserDefaults setInteger:endHour forKey:kEndHour];
    [NSUserDefaults.standardUserDefaults synchronize];
    [self recompute];
}

- (void)setEndMinute:(NSInteger)endMinute {
    _endMinute = endMinute;
    [NSUserDefaults.standardUserDefaults setInteger:endMinute forKey:kEndMinute];
    [NSUserDefaults.standardUserDefaults synchronize];
    [self recompute];
}

- (void)setReminderIntervalMinutes:(NSInteger)reminderIntervalMinutes {
    NSInteger normalized = reminderIntervalMinutes == 15 || reminderIntervalMinutes == 30 || reminderIntervalMinutes == 60 ? reminderIntervalMinutes : 60;
    _reminderIntervalMinutes = normalized;
    [NSUserDefaults.standardUserDefaults setInteger:normalized forKey:kReminderIntervalMinutes];
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (void)setLunchStartHour:(NSInteger)lunchStartHour {
    _lunchStartHour = lunchStartHour;
    [NSUserDefaults.standardUserDefaults setInteger:lunchStartHour forKey:kLunchStartHour];
}

- (void)setLunchStartMinute:(NSInteger)lunchStartMinute {
    _lunchStartMinute = lunchStartMinute;
    [NSUserDefaults.standardUserDefaults setInteger:lunchStartMinute forKey:kLunchStartMinute];
}

- (void)setLunchEndHour:(NSInteger)lunchEndHour {
    _lunchEndHour = lunchEndHour;
    [NSUserDefaults.standardUserDefaults setInteger:lunchEndHour forKey:kLunchEndHour];
}

- (void)setLunchEndMinute:(NSInteger)lunchEndMinute {
    _lunchEndMinute = lunchEndMinute;
    [NSUserDefaults.standardUserDefaults setInteger:lunchEndMinute forKey:kLunchEndMinute];
}

- (void)setDailyTargetMl:(NSInteger)dailyTargetMl {
    _dailyTargetMl = MIN(kDailyTargetMaxMl, MAX(500, dailyTargetMl));
    [NSUserDefaults.standardUserDefaults setInteger:_dailyTargetMl forKey:kDailyTargetMl];
    [NSUserDefaults.standardUserDefaults synchronize];
    [self recompute];
}

- (void)setCompletedTodayMl:(NSInteger)completedTodayMl {
    _completedTodayMl = MIN(kDailyTargetMaxMl, MAX(0, completedTodayMl));
    [NSUserDefaults.standardUserDefaults setInteger:_completedTodayMl forKey:kCompletedTodayMl];
}

- (NSInteger)workHours {
    NSInteger startMinutes = self.startHour * 60;
    NSInteger endMinutes = self.endHour * 60 + self.endMinute;
    return MAX(1, (NSInteger)ceil((double)(endMinutes - startMinutes) / 60.0));
}

- (void)recompute {
    NSInteger startMinutes = _startHour * 60;
    NSInteger endMinutes = _endHour * 60 + _endMinute;
    if (endMinutes <= startMinutes) {
        _endHour = MIN(24, _startHour + 1);
        _endMinute = 0;
        [NSUserDefaults.standardUserDefaults setInteger:_endHour forKey:kEndHour];
        [NSUserDefaults.standardUserDefaults setInteger:_endMinute forKey:kEndMinute];
        [NSUserDefaults.standardUserDefaults synchronize];
    }
    _reminderAmountMl = kReminderAmountMl;
}

- (void)updateWorkStartHour:(NSInteger)startHour endHour:(NSInteger)endHour endMinute:(NSInteger)endMinute {
    _startHour = MAX(0, MIN(23, startHour));
    _endHour = MAX(0, MIN(24, endHour));
    _endMinute = endMinute >= 30 ? 30 : 0;
    [self recompute];

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setInteger:_startHour forKey:kStartHour];
    [defaults setInteger:_endHour forKey:kEndHour];
    [defaults setInteger:_endMinute forKey:kEndMinute];
    [defaults synchronize];
}

- (void)updateLunchStartHour:(NSInteger)startHour startMinute:(NSInteger)startMinute endHour:(NSInteger)endHour endMinute:(NSInteger)endMinute {
    _lunchStartHour = MAX(0, MIN(23, startHour));
    _lunchStartMinute = startMinute >= 30 ? 30 : 0;
    _lunchEndHour = MAX(0, MIN(24, endHour));
    _lunchEndMinute = endMinute >= 30 ? 30 : 0;

    NSInteger startTotal = _lunchStartHour * 60 + _lunchStartMinute;
    NSInteger endTotal = _lunchEndHour * 60 + _lunchEndMinute;
    if (endTotal <= startTotal) {
        _lunchEndHour = MIN(24, _lunchStartHour + 1);
        _lunchEndMinute = _lunchStartMinute;
    }

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setInteger:_lunchStartHour forKey:kLunchStartHour];
    [defaults setInteger:_lunchStartMinute forKey:kLunchStartMinute];
    [defaults setInteger:_lunchEndHour forKey:kLunchEndHour];
    [defaults setInteger:_lunchEndMinute forKey:kLunchEndMinute];
    [defaults synchronize];
}

- (void)updateDailyTargetMl:(NSInteger)targetMl {
    self.dailyTargetMl = targetMl;
    [self syncCompletedTodayFromRecords];
}

- (void)updateReminderIntervalMinutes:(NSInteger)minutes {
    self.reminderIntervalMinutes = minutes;
}

- (void)resetIfNeeded {
    NSString *today = [self dayStamp:[NSDate date]];
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:kLastResetDay];
    if (![saved isEqualToString:today]) {
        [NSUserDefaults.standardUserDefaults setObject:today forKey:kLastResetDay];
    }
    [self syncCompletedTodayFromRecords];
}

- (void)completeCurrentReminder {
    [self recordDrinkAmount:self.reminderAmountMl];
}

- (void)recordDrinkAmount:(NSInteger)amount {
    [self resetIfNeeded];
    NSInteger safeAmount = MIN(MAX(0, amount), self.dailyTargetMl - self.completedTodayMl);
    if (safeAmount > 0) {
        [self appendDrinkRecordWithAmount:safeAmount kind:@"drink"];
    }
    [self syncCompletedTodayFromRecords];
}

- (void)setTodayTotalByManualAdjustment:(NSInteger)targetMl {
    [self resetIfNeeded];
    NSInteger clampedTarget = MIN(self.dailyTargetMl, MAX(0, targetMl));
    NSInteger diff = clampedTarget - self.completedTodayMl;
    if (diff != 0) {
        [self appendDrinkRecordWithAmount:diff kind:@"manual"];
    }
    [self syncCompletedTodayFromRecords];
}

- (NSArray<NSDictionary *> *)drinkRecords {
    NSArray *records = [NSUserDefaults.standardUserDefaults arrayForKey:kDrinkRecords];
    return records ?: @[];
}

- (void)appendDrinkRecordWithAmount:(NSInteger)amount kind:(NSString *)kind {
    NSMutableArray *records = [[self drinkRecords] mutableCopy];
    [records addObject:@{
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
        @"amount": @(amount),
        @"kind": kind ?: @"drink"
    }];
    [NSUserDefaults.standardUserDefaults setObject:records forKey:kDrinkRecords];
}

- (NSInteger)totalForDayStamp:(NSString *)stamp {
    NSInteger total = 0;
    for (NSDictionary *record in [self drinkRecords]) {
        NSNumber *timestamp = record[@"timestamp"];
        NSNumber *amount = record[@"amount"];
        if (!timestamp || !amount) { continue; }
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue];
        if ([[self dayStamp:date] isEqualToString:stamp]) {
            total += amount.integerValue;
        }
    }
    return MIN(self.dailyTargetMl, MAX(0, total));
}

- (void)syncCompletedTodayFromRecords {
    NSString *today = [self dayStamp:[NSDate date]];
    self.completedTodayMl = [self totalForDayStamp:today];
}

- (NSArray<NSDictionary *> *)dailyTotalsForLastDays:(NSInteger)dayCount {
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDate *today = [NSDate date];
    NSMutableArray *totals = [NSMutableArray array];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.dateFormat = @"MM/dd";

    for (NSInteger offset = dayCount - 1; offset >= 0; offset--) {
        NSDate *date = [calendar dateByAddingUnit:NSCalendarUnitDay value:-offset toDate:today options:0];
        NSString *stamp = [self dayStamp:date];
        [totals addObject:@{
            @"label": [formatter stringFromDate:date],
            @"amount": @([self totalForDayStamp:stamp])
        }];
    }
    return totals;
}

- (NSArray<NSDictionary *> *)hourlyTotalsForToday {
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSString *today = [self dayStamp:[NSDate date]];
    NSMutableDictionary<NSNumber *, NSNumber *> *hourTotals = [NSMutableDictionary dictionary];

    for (NSDictionary *record in [self drinkRecords]) {
        NSNumber *timestamp = record[@"timestamp"];
        NSNumber *amount = record[@"amount"];
        if (!timestamp || !amount || amount.integerValue <= 0) { continue; }
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue];
        if (![[self dayStamp:date] isEqualToString:today]) { continue; }
        NSInteger hour = [calendar component:NSCalendarUnitHour fromDate:date];
        NSNumber *key = @(hour);
        NSInteger total = (hourTotals[key] ?: @0).integerValue + amount.integerValue;
        hourTotals[key] = @(total);
    }

    NSMutableArray *result = [NSMutableArray array];
    NSInteger start = self.startHour;
    NSInteger end = self.endHour + (self.endMinute > 0 ? 1 : 0);
    for (NSInteger hour = start; hour <= MIN(23, end); hour++) {
        [result addObject:@{
            @"hour": @(hour),
            @"amount": hourTotals[@(hour)] ?: @0
        }];
    }
    return result;
}

- (NSDate *)nextReminderDate {
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDate *now = [NSDate date];
    NSDateComponents *dayParts = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:now];
    NSDate *todayCandidate = [self nextReminderDateOnDay:dayParts after:now calendar:calendar];
    if (todayCandidate) { return todayCandidate; }

    NSDate *tomorrow = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:now options:0];
    NSDateComponents *tomorrowParts = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:tomorrow];
    return [self nextReminderDateOnDay:tomorrowParts after:nil calendar:calendar];
}

- (NSDate *)nextReminderDateOnDay:(NSDateComponents *)dayParts after:(NSDate *)date calendar:(NSCalendar *)calendar {
    NSDateComponents *startParts = [dayParts copy];
    startParts.hour = self.startHour;
    startParts.minute = 0;
    startParts.second = 0;
    NSDate *startDate = [calendar dateFromComponents:startParts];

    NSDateComponents *endParts = [dayParts copy];
    endParts.hour = self.endHour;
    endParts.minute = self.endMinute;
    endParts.second = 0;
    NSDate *endDate = [calendar dateFromComponents:endParts];

    NSDateComponents *lunchStartParts = [dayParts copy];
    lunchStartParts.hour = self.lunchStartHour;
    lunchStartParts.minute = self.lunchStartMinute;
    lunchStartParts.second = 0;
    NSDate *lunchStartDate = [calendar dateFromComponents:lunchStartParts];

    NSDateComponents *lunchEndParts = [dayParts copy];
    lunchEndParts.hour = self.lunchEndHour;
    lunchEndParts.minute = self.lunchEndMinute;
    lunchEndParts.second = 0;
    NSDate *lunchEndDate = [calendar dateFromComponents:lunchEndParts];

    NSDate *candidate = startDate;
    NSInteger interval = MAX(15, self.reminderIntervalMinutes);
    while ([candidate compare:endDate] == NSOrderedAscending) {
        if ([candidate compare:lunchStartDate] != NSOrderedAscending && [candidate compare:lunchEndDate] == NSOrderedAscending) {
            candidate = lunchEndDate;
            continue;
        }
        if (!date || [candidate compare:date] == NSOrderedDescending) {
            return candidate;
        }
        candidate = [calendar dateByAddingUnit:NSCalendarUnitMinute value:interval toDate:candidate options:0];
    }
    return nil;
}

- (NSString *)nextReminderText {
    NSDate *next = [self nextReminderDate];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.dateFormat = [NSCalendar.currentCalendar isDateInToday:next] ? @"今天 HH:mm" : @"明天 HH:mm";
    return [formatter stringFromDate:next];
}

- (double)progress {
    return MIN(1.0, (double)self.completedTodayMl / (double)MAX(1, self.dailyTargetMl));
}

- (NSString *)dayStamp:(NSDate *)date {
    NSDateComponents *parts = [NSCalendar.currentCalendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:date];
    return [NSString stringWithFormat:@"%ld-%ld-%ld", parts.year, parts.month, parts.day];
}

@end

@interface ScaleView : NSView
@property (nonatomic) NSInteger maxValue;
@end

@implementation ScaleView

- (BOOL)isFlipped { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSInteger maxValue = MAX(100, self.maxValue);
    CGFloat left = 8;
    CGFloat right = self.bounds.size.width - 8;
    CGFloat width = right - left;
    CGFloat baseline = 10;
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:9 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: NSColor.secondaryLabelColor
    };

    [NSColor.tertiaryLabelColor setStroke];
    NSBezierPath *axis = [NSBezierPath bezierPath];
    [axis moveToPoint:NSMakePoint(left, baseline)];
    [axis lineToPoint:NSMakePoint(right, baseline)];
    [axis stroke];

    NSInteger labelStep = maxValue <= 2400 ? 200 : 500;
    for (NSInteger value = 0; value <= maxValue; value += 100) {
        CGFloat x = left + width * ((CGFloat)value / (CGFloat)maxValue);
        BOOL major = value % labelStep == 0 || value == maxValue;
        CGFloat tickHeight = major ? 8 : 4;

        NSBezierPath *tick = [NSBezierPath bezierPath];
        [tick moveToPoint:NSMakePoint(x, baseline)];
        [tick lineToPoint:NSMakePoint(x, baseline + tickHeight)];
        [tick stroke];

        if (major) {
            NSString *label = [NSString stringWithFormat:@"%ld", value];
            NSSize size = [label sizeWithAttributes:attrs];
            CGFloat labelX = MIN(MAX(x - size.width / 2, 0), self.bounds.size.width - size.width);
            [label drawAtPoint:NSMakePoint(labelX, 22) withAttributes:attrs];
        }
    }
}

@end

@interface DrinkChartView : NSView
@property (nonatomic, strong) WaterModel *model;
@property (nonatomic) BOOL weeklyMode;
- (instancetype)initWithModel:(WaterModel *)model;
@end

@implementation DrinkChartView

- (instancetype)initWithModel:(WaterModel *)model {
    self = [super initWithFrame:NSMakeRect(0, 0, 300, 130)];
    if (!self) { return nil; }
    self.model = model;
    self.wantsLayer = YES;
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSArray<NSDictionary *> *totals = self.weeklyMode ? [self.model dailyTotalsForLastDays:7] : [self.model hourlyTotalsForToday];
    if (totals.count == 0) { return; }

    NSRect plot = NSInsetRect(self.bounds, 10, 18);
    plot.size.height -= 14;
    CGFloat gap = 8;
    CGFloat barWidth = (plot.size.width - gap * (totals.count - 1)) / totals.count;

    NSDictionary *labelAttrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:9 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: NSColor.secondaryLabelColor
    };
    NSDictionary *amountAttrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: NSColor.labelColor
    };

    [[NSColor separatorColor] setStroke];
    NSBezierPath *axis = [NSBezierPath bezierPath];
    [axis moveToPoint:NSMakePoint(plot.origin.x, plot.origin.y + plot.size.height)];
    [axis lineToPoint:NSMakePoint(plot.origin.x + plot.size.width, plot.origin.y + plot.size.height)];
    [axis stroke];

    for (NSUInteger i = 0; i < totals.count; i++) {
        NSDictionary *entry = totals[i];
        NSInteger amount = [entry[@"amount"] integerValue];
        NSInteger maxAmount = MAX(1, self.weeklyMode ? self.model.dailyTargetMl : [[totals valueForKeyPath:@"@max.amount"] integerValue]);
        CGFloat ratio = MIN(1.0, (CGFloat)amount / (CGFloat)maxAmount);
        CGFloat barHeight = MAX(amount > 0 ? 6 : 2, plot.size.height * ratio);
        CGFloat x = plot.origin.x + i * (barWidth + gap);
        CGFloat y = plot.origin.y + plot.size.height - barHeight;
        NSRect bar = NSMakeRect(x, y, barWidth, barHeight);
        NSBezierPath *barPath = [NSBezierPath bezierPathWithRoundedRect:bar xRadius:4 yRadius:4];
        NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedRed:0.30 green:0.76 blue:1.0 alpha:1]
                                                             endingColor:[NSColor colorWithCalibratedRed:0.02 green:0.36 blue:0.86 alpha:1]];
        [gradient drawInBezierPath:barPath angle:90];

        NSString *amountText = amount > 0 ? [NSString stringWithFormat:@"%ldml", amount] : @"0ml";
        NSSize amountSize = [amountText sizeWithAttributes:amountAttrs];
        [amountText drawAtPoint:NSMakePoint(x + (barWidth - amountSize.width) / 2, MAX(0, y - 15)) withAttributes:amountAttrs];

        NSString *label = self.weeklyMode ? (entry[@"label"] ?: @"") : [NSString stringWithFormat:@"%02ld", [entry[@"hour"] integerValue]];
        NSSize labelSize = [label sizeWithAttributes:labelAttrs];
        [label drawAtPoint:NSMakePoint(x + (barWidth - labelSize.width) / 2, plot.origin.y + plot.size.height + 4) withAttributes:labelAttrs];
    }
}

@end

@interface CupView : NSView
@property (nonatomic, strong) WaterModel *model;
@property (nonatomic, strong) NSTimer *animationTimer;
@property (nonatomic, strong) NSDate *celebrationStartDate;
@property (nonatomic) CGFloat wavePhase;
@property (nonatomic) CGFloat displayProgressOverride;
- (void)celebrate;
@end

@implementation CupView

- (instancetype)initWithModel:(WaterModel *)model {
    self = [super initWithFrame:NSMakeRect(0, 0, 130, 170)];
    if (!self) { return nil; }
    self.model = model;
    self.displayProgressOverride = -1;
    self.wantsLayer = YES;
    [self startAnimating];
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)dealloc {
    [self.animationTimer invalidate];
}

- (void)startAnimating {
    self.animationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        self.wavePhase += 0.12;
        if (self.wavePhase > M_PI * 2) {
            self.wavePhase -= M_PI * 2;
        }
        [self setNeedsDisplay:YES];
    }];
}

- (void)celebrate {
    self.celebrationStartDate = [NSDate date];
    self.wavePhase += 1.2;
    [self setNeedsDisplay:YES];
}

- (NSBezierPath *)wavePathInRect:(NSRect)rect amplitude:(CGFloat)amplitude phase:(CGFloat)phase yOffset:(CGFloat)yOffset {
    CGFloat top = rect.origin.y + yOffset;
    CGFloat left = rect.origin.x;
    CGFloat right = rect.origin.x + rect.size.width;
    CGFloat bottom = rect.origin.y + rect.size.height;
    CGFloat width = rect.size.width;

    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(left, top)];

    for (CGFloat x = left; x <= right; x += 2) {
        CGFloat normalized = (x - left) / width;
        CGFloat y = top + sin(normalized * M_PI * 2.0 + phase) * amplitude;
        [path lineToPoint:NSMakePoint(x, y)];
    }

    [path lineToPoint:NSMakePoint(right, bottom)];
    [path lineToPoint:NSMakePoint(left, bottom)];
    [path closePath];
    return path;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    CGFloat celebrationAge = self.celebrationStartDate ? -self.celebrationStartDate.timeIntervalSinceNow : 100;
    BOOL celebrating = celebrationAge < 1.25;
    CGFloat celebrationProgress = celebrating ? MIN(1.0, celebrationAge / 1.25) : 1.0;

    CGFloat progress = self.displayProgressOverride >= 0 ? self.displayProgressOverride : self.model.progress;
    progress = MIN(1.0, MAX(0.0, progress));
    NSRect cup = NSMakeRect(17, 12, 96, 144);
    NSBezierPath *glass = [NSBezierPath bezierPathWithRoundedRect:cup xRadius:25 yRadius:25];
    NSShadow *shadow = [NSShadow new];
    shadow.shadowColor = [NSColor colorWithCalibratedWhite:0 alpha:0.28];
    shadow.shadowBlurRadius = 8;
    shadow.shadowOffset = NSMakeSize(0, -3);
    [NSGraphicsContext saveGraphicsState];
    [shadow set];
    [[NSColor colorWithCalibratedWhite:1 alpha:0.10] setFill];
    [glass fill];
    [NSGraphicsContext restoreGraphicsState];

    NSGradient *glassGradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:1 alpha:0.18]
                                                               endingColor:[NSColor colorWithCalibratedWhite:1 alpha:0.04]];
    [glassGradient drawInBezierPath:glass angle:0];

    CGFloat innerInset = 5;
    NSRect waterBounds = NSInsetRect(cup, innerInset, innerInset);
    CGFloat fillHeight = MAX(12, waterBounds.size.height * progress);
    CGFloat waterTop = waterBounds.origin.y + waterBounds.size.height - fillHeight;
    NSRect water = NSMakeRect(waterBounds.origin.x, waterTop, waterBounds.size.width, fillHeight);
    NSBezierPath *clipPath = [NSBezierPath bezierPathWithRoundedRect:waterBounds xRadius:21 yRadius:21];

    [NSGraphicsContext saveGraphicsState];
    [clipPath addClip];

    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedRed:0.18 green:0.74 blue:0.96 alpha:1]
                                                         endingColor:[NSColor colorWithCalibratedRed:0.02 green:0.35 blue:0.78 alpha:1]];
    [gradient drawInRect:water angle:90];

    CGFloat amplitude = fillHeight < 28 ? 2.0 : 4.0;
    if (celebrating) {
        amplitude += 5.0 * (1.0 - celebrationProgress);
    }
    NSBezierPath *frontWave = [self wavePathInRect:water amplitude:amplitude phase:self.wavePhase yOffset:amplitude + 2];
    [[NSColor colorWithCalibratedRed:0.09 green:0.55 blue:0.91 alpha:0.78] setFill];
    [frontWave fill];

    NSBezierPath *highlightWave = [self wavePathInRect:water amplitude:amplitude * 0.7 phase:-self.wavePhase * 1.35 yOffset:amplitude + 7];
    [[NSColor colorWithCalibratedRed:0.66 green:0.92 blue:1.0 alpha:0.35] setFill];
    [highlightWave fill];

    NSBezierPath *shine = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(water.origin.x + 12, water.origin.y + 12, 12, MAX(26, water.size.height * 0.42)) xRadius:6 yRadius:6];
    [[NSColor colorWithCalibratedWhite:1 alpha:0.22] setFill];
    [shine fill];

    NSArray<NSDictionary *> *bubbles = @[
        @{@"x": @0.22, @"size": @3.0, @"speed": @0.50, @"phase": @0.05},
        @{@"x": @0.36, @"size": @2.0, @"speed": @0.72, @"phase": @0.31},
        @{@"x": @0.54, @"size": @3.8, @"speed": @0.44, @"phase": @0.58},
        @{@"x": @0.68, @"size": @2.4, @"speed": @0.66, @"phase": @0.82},
        @{@"x": @0.80, @"size": @2.8, @"speed": @0.56, @"phase": @0.18},
        @{@"x": @0.44, @"size": @1.7, @"speed": @0.86, @"phase": @0.74}
    ];
    CGFloat bubbleTravel = MAX(1, water.size.height - amplitude * 2 - 10);
    for (NSDictionary *bubble in bubbles) {
        CGFloat progress = fmod(self.wavePhase * [bubble[@"speed"] doubleValue] / (M_PI * 2.0) + [bubble[@"phase"] doubleValue], 1.0);
        CGFloat radius = [bubble[@"size"] doubleValue];
        CGFloat x = water.origin.x + water.size.width * [bubble[@"x"] doubleValue] + sin(self.wavePhase * 1.7 + progress * 5.0) * 3.0;
        CGFloat y = water.origin.y + water.size.height - 8 - bubbleTravel * progress;
        CGFloat edgeFade = MIN(1.0, MIN(progress * 4.0, (1.0 - progress) * 5.0));
        NSRect bubbleRect = NSMakeRect(x - radius, y - radius, radius * 2, radius * 2);
        NSBezierPath *bubblePath = [NSBezierPath bezierPathWithOvalInRect:bubbleRect];
        [[NSColor colorWithCalibratedWhite:1 alpha:0.26 * edgeFade] setFill];
        [bubblePath fill];
        [[NSColor colorWithCalibratedWhite:1 alpha:0.52 * edgeFade] setStroke];
        bubblePath.lineWidth = 0.8;
        [bubblePath stroke];
    }

    [NSGraphicsContext restoreGraphicsState];

    NSBezierPath *leftShine = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMinX(cup) + 24, NSMinY(cup) + 44, 12, 48) xRadius:7 yRadius:7];
    [[NSColor colorWithCalibratedWhite:1 alpha:0.30] setFill];
    [leftShine fill];
    NSBezierPath *rightShade = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMaxX(cup) - 24, NSMinY(cup) + 32, 7, 88) xRadius:4 yRadius:4];
    [[NSColor colorWithCalibratedWhite:0 alpha:0.06] setFill];
    [rightShade fill];

    [[NSColor colorWithCalibratedWhite:0.08 alpha:0.92] setStroke];
    glass.lineWidth = 3;
    [glass stroke];

    NSBezierPath *rim = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMinX(cup) + 7, NSMinY(cup) + 1, NSWidth(cup) - 14, 12) xRadius:6 yRadius:6];
    [[NSColor colorWithCalibratedWhite:1 alpha:0.24] setFill];
    [rim fill];
    [[NSColor colorWithCalibratedWhite:0.08 alpha:0.54] setStroke];
    rim.lineWidth = 1.2;
    [rim stroke];

    if (celebrating) {
        CGFloat alpha = 1.0 - celebrationProgress;
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(cup, -10 - 14 * celebrationProgress, -10 - 14 * celebrationProgress)];
        [[NSColor colorWithCalibratedRed:0.32 green:0.78 blue:1.0 alpha:0.34 * alpha] setStroke];
        ring.lineWidth = 3;
        [ring stroke];

        NSArray<NSNumber *> *drops = @[@0.16, @0.32, @0.48, @0.64, @0.80];
        for (NSUInteger i = 0; i < drops.count; i++) {
            CGFloat seed = drops[i].doubleValue;
            CGFloat x = cup.origin.x + cup.size.width * seed + sin(self.wavePhase + i) * 5;
            CGFloat y = cup.origin.y + cup.size.height * 0.72 - celebrationProgress * (34 + i * 5);
            CGFloat radius = 2.5 + (i % 2);
            NSRect dropRect = NSMakeRect(x, y, radius * 2, radius * 2);
            NSBezierPath *drop = [NSBezierPath bezierPathWithOvalInRect:dropRect];
            [[NSColor colorWithCalibratedRed:0.62 green:0.90 blue:1.0 alpha:0.78 * alpha] setFill];
            [drop fill];
        }
    }

    NSString *text = [NSString stringWithFormat:@"%ld%%", (NSInteger)llround(progress * 100)];
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:22 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: NSColor.whiteColor
    };
    NSSize size = [text sizeWithAttributes:attrs];
    [text drawAtPoint:NSMakePoint((self.bounds.size.width - size.width) / 2, 72) withAttributes:attrs];
}

@end

@interface PanelController : NSViewController
@property (nonatomic, strong) WaterModel *model;
@property (nonatomic, strong) CupView *cupView;
@property (nonatomic, strong) NSTextField *amountLabel;
@property (nonatomic, strong) NSTextField *hintLabel;
@property (nonatomic, strong) NSTextField *targetLabel;
@property (nonatomic, strong) NSPopUpButton *startPopup;
@property (nonatomic, strong) NSPopUpButton *endPopup;
@property (nonatomic, strong) NSSlider *amountSlider;
@property (nonatomic, strong) ScaleView *scaleView;
@property (nonatomic, strong) DrinkChartView *chartView;
@property (nonatomic, strong) NSTextField *chartLabel;
@property (nonatomic, strong) NSSegmentedControl *chartModeControl;
@property (copy) void (^settingsHandler)(void);
@property (copy) void (^testHandler)(void);
@end

@implementation PanelController

- (instancetype)initWithModel:(WaterModel *)model settings:(void (^)(void))settings test:(void (^)(void))test {
    self = [super initWithNibName:nil bundle:nil];
    if (!self) { return nil; }
    self.model = model;
    self.settingsHandler = settings;
    self.testHandler = test;
    return self;
}

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 340, 610)];
    view.wantsLayer = YES;
    self.view = view;

    self.cupView = [[CupView alloc] initWithModel:self.model];
    self.cupView.frame = NSMakeRect(105, 430, 130, 170);
    [view addSubview:self.cupView];

    self.amountLabel = [self labelWithFrame:NSMakeRect(20, 404, 300, 22) font:[NSFont systemFontOfSize:15 weight:NSFontWeightSemibold] color:NSColor.labelColor alignment:NSTextAlignmentCenter];
    [view addSubview:self.amountLabel];

    self.hintLabel = [self labelWithFrame:NSMakeRect(20, 382, 300, 18) font:[NSFont systemFontOfSize:12] color:NSColor.secondaryLabelColor alignment:NSTextAlignmentCenter];
    [view addSubview:self.hintLabel];

    NSBox *line = [[NSBox alloc] initWithFrame:NSMakeRect(18, 362, 304, 1)];
    line.boxType = NSBoxSeparator;
    [view addSubview:line];

    NSTextField *workLabel = [self labelWithFrame:NSMakeRect(24, 326, 80, 24) font:[NSFont systemFontOfSize:13] color:NSColor.labelColor alignment:NSTextAlignmentLeft];
    workLabel.stringValue = @"工作时间";
    [view addSubview:workLabel];

    self.startPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(104, 324, 86, 28)];
    self.endPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(224, 324, 86, 28)];
    for (NSInteger i = 0; i < 24; i++) {
        [self.startPopup addItemWithTitle:[NSString stringWithFormat:@"%02ld:00", i]];
    }
    for (NSInteger i = 1; i <= 48; i++) {
        NSInteger totalMinutes = i * 30;
        NSInteger hour = totalMinutes / 60;
        NSInteger minute = totalMinutes % 60;
        [self.endPopup addItemWithTitle:[NSString stringWithFormat:@"%02ld:%02ld", hour, minute]];
    }
    [self.startPopup setTarget:self];
    [self.endPopup setTarget:self];
    [self.startPopup setAction:@selector(settingsChanged:)];
    [self.endPopup setAction:@selector(settingsChanged:)];
    [view addSubview:self.startPopup];
    [view addSubview:self.endPopup];

    NSTextField *toLabel = [self labelWithFrame:NSMakeRect(198, 328, 20, 20) font:[NSFont systemFontOfSize:13] color:NSColor.secondaryLabelColor alignment:NSTextAlignmentCenter];
    toLabel.stringValue = @"到";
    [view addSubview:toLabel];

    NSTextField *dailyLabel = [self labelWithFrame:NSMakeRect(24, 288, 80, 24) font:[NSFont systemFontOfSize:13] color:NSColor.labelColor alignment:NSTextAlignmentLeft];
    dailyLabel.stringValue = @"当前已喝";
    [view addSubview:dailyLabel];

    self.targetLabel = [self labelWithFrame:NSMakeRect(202, 290, 108, 20) font:[NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular] color:NSColor.labelColor alignment:NSTextAlignmentRight];
    [view addSubview:self.targetLabel];

    self.amountSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(22, 258, 296, 24)];
    self.amountSlider.minValue = 0;
    self.amountSlider.allowsTickMarkValuesOnly = YES;
    self.amountSlider.target = self;
    self.amountSlider.action = @selector(amountSliderChanged:);
    [view addSubview:self.amountSlider];

    self.scaleView = [[ScaleView alloc] initWithFrame:NSMakeRect(20, 214, 300, 40)];
    [view addSubview:self.scaleView];

    self.chartLabel = [self labelWithFrame:NSMakeRect(24, 178, 160, 22) font:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold] color:NSColor.labelColor alignment:NSTextAlignmentLeft];
    [view addSubview:self.chartLabel];

    self.chartModeControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(204, 176, 112, 26)];
    [self.chartModeControl setSegmentCount:2];
    [self.chartModeControl setLabel:@"今天" forSegment:0];
    [self.chartModeControl setLabel:@"本周" forSegment:1];
    [self.chartModeControl setSelectedSegment:0];
    self.chartModeControl.target = self;
    self.chartModeControl.action = @selector(chartModeChanged:);
    [view addSubview:self.chartModeControl];

    self.chartView = [[DrinkChartView alloc] initWithModel:self.model];
    self.chartView.frame = NSMakeRect(20, 42, 300, 130);
    [view addSubview:self.chartView];

    NSButton *resetButton = [self buttonWithTitle:@"重置今天" frame:NSMakeRect(22, 8, 92, 28) action:@selector(resetPressed:)];
    resetButton.bezelStyle = NSBezelStyleInline;
    [view addSubview:resetButton];

    NSButton *clearCacheButton = [self buttonWithTitle:@"清缓存并退出" frame:NSMakeRect(122, 8, 118, 28) action:@selector(clearCacheAndQuitPressed:)];
    clearCacheButton.bezelStyle = NSBezelStyleInline;
    [view addSubview:clearCacheButton];

    NSButton *quitButton = [self buttonWithTitle:@"退出" frame:NSMakeRect(260, 8, 58, 28) action:@selector(quitPressed:)];
    quitButton.bezelStyle = NSBezelStyleInline;
    [view addSubview:quitButton];

    [self refresh];
}

- (NSTextField *)labelWithFrame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color alignment:(NSTextAlignment)alignment {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.font = font;
    label.textColor = color;
    label.alignment = alignment;
    return label;
}

- (NSButton *)buttonWithTitle:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.target = self;
    button.action = action;
    button.bezelStyle = NSBezelStyleRounded;
    return button;
}

- (void)refresh {
    [self.model resetIfNeeded];
    [self.model recompute];
    self.amountLabel.stringValue = [NSString stringWithFormat:@"当前已喝 %ld / %ld ml", self.model.completedTodayMl, self.model.dailyTargetMl];
    self.hintLabel.stringValue = [NSString stringWithFormat:@"每 %ld 分钟提醒 · 午休 %02ld:%02ld-%02ld:%02ld · 下次 %@",
                                  self.model.reminderIntervalMinutes,
                                  self.model.lunchStartHour,
                                  self.model.lunchStartMinute,
                                  self.model.lunchEndHour,
                                  self.model.lunchEndMinute,
                                  [self.model nextReminderText]];
    self.targetLabel.stringValue = [NSString stringWithFormat:@"%ld ml", self.model.completedTodayMl];
    [self.startPopup selectItemAtIndex:self.model.startHour];
    NSInteger endIndex = self.model.endHour * 2 + (self.model.endMinute >= 30 ? 1 : 0) - 1;
    [self.endPopup selectItemAtIndex:MAX(0, MIN(47, endIndex))];
    self.amountSlider.maxValue = self.model.dailyTargetMl;
    self.amountSlider.numberOfTickMarks = self.model.dailyTargetMl / 100 + 1;
    self.amountSlider.integerValue = self.model.completedTodayMl;
    self.scaleView.maxValue = self.model.dailyTargetMl;
    self.chartView.weeklyMode = self.chartModeControl.selectedSegment == 1;
    self.chartLabel.stringValue = self.chartView.weeklyMode ? @"本周喝水记录" : @"今天每小时喝水";
    [self.cupView setNeedsDisplay:YES];
    [self.scaleView setNeedsDisplay:YES];
    [self.chartView setNeedsDisplay:YES];
}

- (void)settingsChanged:(id)sender {
    NSInteger endTotalMinutes = (self.endPopup.indexOfSelectedItem + 1) * 30;
    [self.model updateWorkStartHour:self.startPopup.indexOfSelectedItem
                             endHour:endTotalMinutes / 60
                           endMinute:endTotalMinutes % 60];
    [self refresh];
    if (self.settingsHandler) { self.settingsHandler(); }
}

- (void)amountSliderChanged:(id)sender {
    NSInteger rounded = (NSInteger)llround((double)self.amountSlider.integerValue / 100.0) * 100;
    [self.model setTodayTotalByManualAdjustment:rounded];
    [self refresh];
}

- (void)chartModeChanged:(id)sender {
    [self refresh];
}

- (void)resetPressed:(id)sender {
    [self.model setTodayTotalByManualAdjustment:0];
    [self refresh];
}

- (void)testPressed:(id)sender {
    if (self.testHandler) { self.testHandler(); }
}

- (void)clearCacheAndQuitPressed:(id)sender {
    NSString *domain = NSBundle.mainBundle.bundleIdentifier ?: @"com.ehousechina.drinktime";
    [NSUserDefaults.standardUserDefaults removePersistentDomainForName:domain];
    [NSUserDefaults.standardUserDefaults synchronize];
    [NSApp terminate:nil];
}

- (void)quitPressed:(id)sender {
    [NSApp terminate:nil];
}

@end

@interface ReminderWindowController : NSWindowController
@property (nonatomic, strong) WaterModel *model;
@property (nonatomic, strong) CupView *cupView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *messageLabel;
@property (nonatomic, strong) NSMutableArray<NSButton *> *amountButtons;
@property (nonatomic, strong) NSButton *snoozeButton;
@property (copy) void (^drinkHandler)(NSInteger amount);
@property (copy) void (^snoozeHandler)(void);
- (instancetype)initWithModel:(WaterModel *)model drink:(void (^)(NSInteger amount))drink snooze:(void (^)(void))snooze;
- (void)refresh;
@end

@implementation ReminderWindowController

- (instancetype)initWithModel:(WaterModel *)model drink:(void (^)(NSInteger amount))drink snooze:(void (^)(void))snooze {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 380, 450)
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    self = [super initWithWindow:window];
    if (!self) { return nil; }
    self.model = model;
    self.drinkHandler = drink;
    self.snoozeHandler = snooze;
    DTConfigureGlassWindow(window);
    [self buildContent];
    return self;
}

- (void)buildContent {
    NSView *view = DTGlassPanel(NSMakeRect(0, 0, 380, 450), 30);
    self.window.contentView = view;

    NSButton *closeButton = [self buttonWithTitle:@"×" frame:NSMakeRect(326, 402, 34, 34) action:@selector(closePressed:)];
    closeButton.bezelStyle = NSBezelStyleCircular;
    closeButton.font = [NSFont systemFontOfSize:18 weight:NSFontWeightBold];
    [view addSubview:closeButton];

    self.titleLabel = [self labelWithFrame:NSMakeRect(24, 404, 332, 28) font:[NSFont systemFontOfSize:20 weight:NSFontWeightBold] color:DTPrimaryTextColor() alignment:NSTextAlignmentCenter];
    self.titleLabel.stringValue = @"该喝水了";
    [view addSubview:self.titleLabel];

    self.cupView = [[CupView alloc] initWithModel:self.model];
    self.cupView.frame = NSMakeRect(125, 226, 130, 170);
    [view addSubview:self.cupView];

    self.messageLabel = [self labelWithFrame:NSMakeRect(24, 180, 332, 38) font:[NSFont systemFontOfSize:14] color:DTSecondaryTextColor() alignment:NSTextAlignmentCenter];
    self.messageLabel.maximumNumberOfLines = 2;
    [view addSubview:self.messageLabel];

    self.amountButtons = [NSMutableArray array];
    NSInteger index = 0;
    for (NSInteger amount = 100; amount <= 550; amount += 50) {
        NSInteger row = index / 5;
        NSInteger col = index % 5;
        NSButton *button = [self buttonWithTitle:[NSString stringWithFormat:@"%ldml", amount]
                                           frame:NSMakeRect(22 + col * 67, 104 - row * 38, 62, 30)
                                          action:@selector(amountPressed:)];
        button.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightSemibold];
        button.tag = amount;
        [self.amountButtons addObject:button];
        [view addSubview:button];
        index++;
    }

    self.snoozeButton = [self buttonWithTitle:@"稍后 5 分钟" frame:NSMakeRect(132, 22, 116, 32) action:@selector(snoozePressed:)];
    [view addSubview:self.snoozeButton];

    [self refresh];
}

- (NSTextField *)labelWithFrame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color alignment:(NSTextAlignment)alignment {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.font = font;
    label.textColor = color;
    label.alignment = alignment;
    return label;
}

- (NSButton *)buttonWithTitle:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.target = self;
    button.action = action;
    button.bezelStyle = NSBezelStyleRounded;
    button.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    button.contentTintColor = DTPrimaryTextColor();
    return button;
}

- (void)refresh {
    [self.model resetIfNeeded];
    [self.model recompute];
    self.titleLabel.stringValue = @"该喝水了";
    self.messageLabel.stringValue = [NSString stringWithFormat:@"准备喝多少呢？\n今天已喝 %ld / %ld ml", self.model.completedTodayMl, self.model.dailyTargetMl];
    for (NSButton *button in self.amountButtons) {
        button.enabled = YES;
    }
    self.snoozeButton.enabled = YES;
    [self.cupView setNeedsDisplay:YES];
}

- (void)amountPressed:(NSButton *)sender {
    for (NSButton *button in self.amountButtons) {
        button.enabled = NO;
    }
    self.snoozeButton.enabled = NO;
    NSInteger amount = sender.tag;
    if (self.drinkHandler) { self.drinkHandler(amount); }
    [self.cupView celebrate];
    self.titleLabel.stringValue = @"完成";
    self.messageLabel.stringValue = [NSString stringWithFormat:@"已记录 %ld ml · %@\n今天已喝 %ld / %ld ml", amount, [self encouragementText], self.model.completedTodayMl, self.model.dailyTargetMl];
    [self performSelector:@selector(close) withObject:nil afterDelay:1.45];
}

- (void)snoozePressed:(id)sender {
    if (self.snoozeHandler) { self.snoozeHandler(); }
    [self close];
}

- (void)closePressed:(id)sender {
    [self close];
}

- (NSString *)encouragementText {
    NSArray<NSString *> *lines = @[
        @"你在认真照顾自己，真不错。",
        @"这一口水，给今天加一点清亮。",
        @"做得好，身体会记得你的温柔。",
        @"小小一杯，也是在给自己充电。",
        @"很稳，今天的你又多照顾了自己一点。",
        @"补水成功，状态正在悄悄变好。",
        @"漂亮，继续这样慢慢把自己养好。",
        @"这一杯到位，疲惫少一点点。",
        @"你没有忽略自己，这很重要。",
        @"好样的，节奏感回来了。"
    ];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *lastLine = [defaults stringForKey:@"lastEncouragementText"];
    NSString *line = lines[arc4random_uniform((uint32_t)lines.count)];
    if (lines.count > 1) {
        while ([line isEqualToString:lastLine]) {
            line = lines[arc4random_uniform((uint32_t)lines.count)];
        }
    }
    [defaults setObject:line forKey:@"lastEncouragementText"];
    return line;
}

@end

@interface SummaryWindowController : NSWindowController
@property (nonatomic, strong) WaterModel *model;
- (instancetype)initWithModel:(WaterModel *)model;
- (void)refresh;
@end

@implementation SummaryWindowController

- (instancetype)initWithModel:(WaterModel *)model {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 380, 460)
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    self = [super initWithWindow:window];
    if (!self) { return nil; }
    self.model = model;
    DTConfigureGlassWindow(window);
    [self refresh];
    return self;
}

- (NSTextField *)labelWithFrame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color alignment:(NSTextAlignment)alignment {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.font = font;
    label.textColor = color;
    label.alignment = alignment;
    return label;
}

- (NSButton *)buttonWithTitle:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.target = self;
    button.action = action;
    button.bezelStyle = NSBezelStyleRounded;
    button.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    button.contentTintColor = DTPrimaryTextColor();
    return button;
}

- (void)refresh {
    [self.model resetIfNeeded];
    NSView *view = DTGlassPanel(NSMakeRect(0, 0, 380, 460), 30);
    self.window.contentView = view;

    NSButton *closeButton = [self buttonWithTitle:@"×" frame:NSMakeRect(326, 412, 34, 34) action:@selector(closePressed:)];
    closeButton.bezelStyle = NSBezelStyleCircular;
    closeButton.font = [NSFont systemFontOfSize:18 weight:NSFontWeightBold];
    [view addSubview:closeButton];

    NSTextField *title = [self labelWithFrame:NSMakeRect(24, 412, 332, 28) font:[NSFont systemFontOfSize:21 weight:NSFontWeightBold] color:DTPrimaryTextColor() alignment:NSTextAlignmentCenter];
    title.stringValue = @"今天喝水统计";
    [view addSubview:title];

    NSTextField *total = [self labelWithFrame:NSMakeRect(24, 374, 332, 24) font:[NSFont systemFontOfSize:15 weight:NSFontWeightSemibold] color:DTSecondaryTextColor() alignment:NSTextAlignmentCenter];
    total.stringValue = [NSString stringWithFormat:@"今日合计 %ld / %ld ml", self.model.completedTodayMl, self.model.dailyTargetMl];
    [view addSubview:total];

    NSArray<NSDictionary *> *hours = [self.model hourlyTotalsForToday];
    CGFloat top = 336;
    CGFloat rowHeight = 24;
    NSInteger maxAmount = 1;
    for (NSDictionary *entry in hours) {
        maxAmount = MAX(maxAmount, [entry[@"amount"] integerValue]);
    }

    for (NSUInteger i = 0; i < hours.count && i < 12; i++) {
        NSDictionary *entry = hours[i];
        NSInteger hour = [entry[@"hour"] integerValue];
        NSInteger amount = [entry[@"amount"] integerValue];
        CGFloat y = top - i * rowHeight;

        NSTextField *hourLabel = [self labelWithFrame:NSMakeRect(30, y, 54, 18) font:[NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular] color:DTSecondaryTextColor() alignment:NSTextAlignmentRight];
        hourLabel.stringValue = [NSString stringWithFormat:@"%02ld:00", hour];
        [view addSubview:hourLabel];

        CGFloat width = amount > 0 ? 180.0 * ((CGFloat)amount / (CGFloat)maxAmount) : 3;
        NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(96, y + 3, width, 12)];
        bar.wantsLayer = YES;
        bar.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.12 green:0.58 blue:0.92 alpha:0.95].CGColor;
        bar.layer.cornerRadius = 6;
        [view addSubview:bar];

        NSTextField *amountLabel = [self labelWithFrame:NSMakeRect(286, y, 64, 18) font:[NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium] color:DTPrimaryTextColor() alignment:NSTextAlignmentRight];
        amountLabel.stringValue = [NSString stringWithFormat:@"%ld ml", amount];
        [view addSubview:amountLabel];
    }

    NSTextField *note = [self labelWithFrame:NSMakeRect(34, 26, 312, 36) font:[NSFont systemFontOfSize:13] color:DTSecondaryTextColor() alignment:NSTextAlignmentCenter];
    note.maximumNumberOfLines = 2;
    note.stringValue = @"辛苦啦。今天的每一杯水，都是你认真照顾自己的证据。";
    [view addSubview:note];
}

- (void)closePressed:(id)sender {
    [self close];
}

@end

@interface PhoneChargeView : NSView
@property (nonatomic, strong) NSTimer *animationTimer;
@property (nonatomic) CGFloat phase;
@end

@implementation PhoneChargeView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) { return nil; }
    self.wantsLayer = YES;
    self.animationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        self.phase += 0.035;
        if (self.phase > 1.0) { self.phase -= 1.0; }
        [self setNeedsDisplay:YES];
    }];
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)dealloc {
    [self.animationTimer invalidate];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    CGFloat ease = 0.5 - cos(self.phase * M_PI * 2.0) * 0.5;
    NSRect phone = NSMakeRect(125, 20, 90, 142);
    NSBezierPath *phonePath = [NSBezierPath bezierPathWithRoundedRect:phone xRadius:22 yRadius:22];
    NSGradient *phoneGradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.14 alpha:1]
                                                               endingColor:[NSColor colorWithCalibratedWhite:0.03 alpha:1]];
    [phoneGradient drawInBezierPath:phonePath angle:90];
    [[NSColor colorWithCalibratedWhite:1 alpha:0.28] setStroke];
    phonePath.lineWidth = 2;
    [phonePath stroke];

    NSRect screen = NSInsetRect(phone, 8, 10);
    NSBezierPath *screenPath = [NSBezierPath bezierPathWithRoundedRect:screen xRadius:16 yRadius:16];
    NSGradient *screenGradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedRed:0.12 green:0.54 blue:0.92 alpha:1]
                                                                endingColor:[NSColor colorWithCalibratedRed:0.36 green:0.88 blue:0.72 alpha:1]];
    [screenGradient drawInBezierPath:screenPath angle:90];

    NSRect battery = NSMakeRect(NSMidX(phone) - 22, NSMinY(phone) + 52, 44, 20);
    NSBezierPath *batteryPath = [NSBezierPath bezierPathWithRoundedRect:battery xRadius:6 yRadius:6];
    [[NSColor colorWithCalibratedWhite:1 alpha:0.86] setStroke];
    batteryPath.lineWidth = 2;
    [batteryPath stroke];
    NSBezierPath *batteryTip = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMaxX(battery) + 3, NSMinY(battery) + 6, 4, 8) xRadius:2 yRadius:2];
    [[NSColor colorWithCalibratedWhite:1 alpha:0.86] setFill];
    [batteryTip fill];
    NSBezierPath *chargeFill = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(battery, 4, 4) xRadius:3 yRadius:3];
    [[NSColor colorWithCalibratedRed:0.32 green:0.95 blue:0.62 alpha:0.88] setFill];
    [chargeFill fill];

    NSDictionary *boltAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:24 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: NSColor.whiteColor
    };
    [@"⚡" drawAtPoint:NSMakePoint(NSMidX(phone) - 10, NSMinY(phone) + 78) withAttributes:boltAttrs];

    CGFloat portY = NSMaxY(phone) - 4;
    NSBezierPath *port = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMidX(phone) - 18, portY, 36, 5) xRadius:2.5 yRadius:2.5];
    [[NSColor colorWithCalibratedWhite:0 alpha:0.42] setFill];
    [port fill];

    CGFloat plugY = portY + 76 - ease * 66;
    CGFloat cableTop = plugY + 35;
    NSBezierPath *cable = [NSBezierPath bezierPath];
    [cable moveToPoint:NSMakePoint(NSMidX(phone), cableTop + 46)];
    [cable curveToPoint:NSMakePoint(NSMidX(phone), plugY + 18)
          controlPoint1:NSMakePoint(NSMidX(phone) - 28, cableTop + 28)
          controlPoint2:NSMakePoint(NSMidX(phone) + 28, plugY + 32)];
    [[NSColor colorWithCalibratedWhite:0.12 alpha:0.72] setStroke];
    cable.lineWidth = 6;
    [cable stroke];
    [[NSColor colorWithCalibratedWhite:1 alpha:0.36] setStroke];
    cable.lineWidth = 2;
    [cable stroke];

    NSRect plugBody = NSMakeRect(NSMidX(phone) - 24, plugY, 48, 28);
    NSBezierPath *plugPath = [NSBezierPath bezierPathWithRoundedRect:plugBody xRadius:9 yRadius:9];
    NSGradient *plugGradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.98 alpha:1]
                                                              endingColor:[NSColor colorWithCalibratedWhite:0.72 alpha:1]];
    [plugGradient drawInBezierPath:plugPath angle:90];
    [[NSColor colorWithCalibratedWhite:0.22 alpha:0.45] setStroke];
    plugPath.lineWidth = 1;
    [plugPath stroke];

    NSBezierPath *connector = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMidX(phone) - 12, plugY - 8, 24, 10) xRadius:4 yRadius:4];
    [[NSColor colorWithCalibratedWhite:0.82 alpha:1] setFill];
    [connector fill];

    if (ease > 0.82) {
        CGFloat pulse = (ease - 0.82) / 0.18;
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(phone, -10 - pulse * 12, -10 - pulse * 12)];
        [[NSColor colorWithCalibratedRed:0.35 green:0.95 blue:0.72 alpha:0.24 * (1.0 - pulse)] setStroke];
        ring.lineWidth = 4;
        [ring stroke];
    }
}

@end

@interface PhoneChargeWindowController : NSWindowController
- (instancetype)init;
@end

@implementation PhoneChargeWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 380, 430)
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    self = [super initWithWindow:window];
    if (!self) { return nil; }
    DTConfigureGlassWindow(window);
    [self buildContent];
    return self;
}

- (NSTextField *)labelWithFrame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color alignment:(NSTextAlignment)alignment {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.font = font;
    label.textColor = color;
    label.alignment = alignment;
    return label;
}

- (NSButton *)buttonWithTitle:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.target = self;
    button.action = action;
    button.bezelStyle = NSBezelStyleRounded;
    button.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    button.contentTintColor = DTPrimaryTextColor();
    return button;
}

- (void)buildContent {
    NSView *view = DTGlassPanel(NSMakeRect(0, 0, 380, 430), 30);
    self.window.contentView = view;

    NSButton *closeButton = [self buttonWithTitle:@"×" frame:NSMakeRect(326, 382, 34, 34) action:@selector(closePressed:)];
    closeButton.bezelStyle = NSBezelStyleCircular;
    closeButton.font = [NSFont systemFontOfSize:18 weight:NSFontWeightBold];
    [view addSubview:closeButton];

    NSTextField *title = [self labelWithFrame:NSMakeRect(24, 374, 332, 28) font:[NSFont systemFontOfSize:21 weight:NSFontWeightBold] color:DTPrimaryTextColor() alignment:NSTextAlignmentCenter];
    title.stringValue = @"下班前充一下电";
    [view addSubview:title];

    NSTextField *subtitle = [self labelWithFrame:NSMakeRect(42, 336, 296, 38) font:[NSFont systemFontOfSize:14] color:DTSecondaryTextColor() alignment:NSTextAlignmentCenter];
    subtitle.maximumNumberOfLines = 2;
    subtitle.stringValue = @"距离下班还有半小时，顺手给手机接上电。";
    [view addSubview:subtitle];

    PhoneChargeView *chargeView = [[PhoneChargeView alloc] initWithFrame:NSMakeRect(20, 120, 340, 190)];
    [view addSubview:chargeView];

    NSButton *okButton = [self buttonWithTitle:@"知道了" frame:NSMakeRect(132, 34, 116, 36) action:@selector(okPressed:)];
    [view addSubview:okButton];
}

- (void)okPressed:(id)sender {
    [self close];
}

- (void)closePressed:(id)sender {
    [self close];
}

@end

@interface OnboardingBubblesView : NSView
@property (nonatomic, strong) NSTimer *animationTimer;
@property (nonatomic) CGFloat phase;
@end

@implementation OnboardingBubblesView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) { return nil; }
    self.wantsLayer = YES;
    self.animationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        self.phase += 0.006;
        if (self.phase > 1.0) { self.phase -= 1.0; }
        [self setNeedsDisplay:YES];
    }];
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)dealloc {
    [self.animationTimer invalidate];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect glow = NSInsetRect(self.bounds, 16, 16);
    NSBezierPath *glowPath = [NSBezierPath bezierPathWithOvalInRect:glow];
    NSGradient *glowGradient = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedRed:0.58 green:0.88 blue:1.0 alpha:0.24],
        [NSColor colorWithCalibratedRed:0.74 green:0.93 blue:1.0 alpha:0.12],
        [NSColor colorWithCalibratedWhite:1 alpha:0.0]
    ]];
    [glowGradient drawInBezierPath:glowPath relativeCenterPosition:NSZeroPoint];

    NSArray<NSDictionary *> *bubbles = @[
        @{@"x": @0.18, @"size": @9.0, @"speed": @0.58, @"phase": @0.05},
        @{@"x": @0.31, @"size": @5.0, @"speed": @0.82, @"phase": @0.44},
        @{@"x": @0.42, @"size": @7.0, @"speed": @0.66, @"phase": @0.72},
        @{@"x": @0.62, @"size": @6.0, @"speed": @0.74, @"phase": @0.18},
        @{@"x": @0.78, @"size": @10.0, @"speed": @0.52, @"phase": @0.36},
        @{@"x": @0.86, @"size": @4.0, @"speed": @0.90, @"phase": @0.63},
        @{@"x": @0.24, @"size": @4.5, @"speed": @0.96, @"phase": @0.88},
        @{@"x": @0.70, @"size": @3.8, @"speed": @1.08, @"phase": @0.02}
    ];

    for (NSDictionary *bubble in bubbles) {
        CGFloat progress = fmod(self.phase * [bubble[@"speed"] doubleValue] + [bubble[@"phase"] doubleValue], 1.0);
        CGFloat radius = [bubble[@"size"] doubleValue];
        CGFloat x = self.bounds.size.width * [bubble[@"x"] doubleValue] + sin((progress + [bubble[@"phase"] doubleValue]) * M_PI * 2.0) * 10.0;
        CGFloat y = self.bounds.size.height + radius - progress * (self.bounds.size.height + radius * 3.0);
        CGFloat alpha = MIN(1.0, MIN(progress * 5.0, (1.0 - progress) * 4.0));
        NSRect bubbleRect = NSMakeRect(x - radius, y - radius, radius * 2, radius * 2);
        NSBezierPath *bubblePath = [NSBezierPath bezierPathWithOvalInRect:bubbleRect];
        [[NSColor colorWithCalibratedRed:0.45 green:0.84 blue:1.0 alpha:0.18 * alpha] setFill];
        [bubblePath fill];
        [[NSColor colorWithCalibratedRed:0.18 green:0.62 blue:0.95 alpha:0.45 * alpha] setStroke];
        bubblePath.lineWidth = 1.2;
        [bubblePath stroke];

        NSBezierPath *shine = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - radius * 0.38, y - radius * 0.45, radius * 0.42, radius * 0.42)];
        [[NSColor colorWithCalibratedWhite:1 alpha:0.46 * alpha] setFill];
        [shine fill];
    }
}

@end

@interface OnboardingWindowController : NSWindowController
@property (nonatomic, strong) WaterModel *model;
@property (nonatomic, strong) NSView *containerView;
@property (nonatomic, strong) NSPopUpButton *startPopup;
@property (nonatomic, strong) NSPopUpButton *endPopup;
@property (nonatomic, strong) NSPopUpButton *lunchStartPopup;
@property (nonatomic, strong) NSPopUpButton *lunchEndPopup;
@property (nonatomic, strong) NSPopUpButton *intervalPopup;
@property (nonatomic, strong) NSSlider *targetSlider;
@property (nonatomic, strong) NSTextField *targetLabel;
@property (nonatomic) NSInteger pageIndex;
@property (copy) void (^finishHandler)(void);
- (instancetype)initWithModel:(WaterModel *)model finish:(void (^)(void))finish;
@end

@implementation OnboardingWindowController

- (NSColor *)primaryTextColor {
    return [NSColor colorWithCalibratedWhite:0.08 alpha:1.0];
}

- (NSColor *)secondaryTextColor {
    return [NSColor colorWithCalibratedWhite:0.24 alpha:1.0];
}

- (NSButton *)pillButtonWithTitle:(NSString *)title frame:(NSRect)frame background:(NSColor *)background foreground:(NSColor *)foreground action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.target = self;
    button.action = action;
    button.bezelStyle = NSBezelStyleRegularSquare;
    button.bordered = NO;
    button.wantsLayer = YES;
    button.layer.backgroundColor = background.CGColor;
    button.layer.cornerRadius = frame.size.height / 2;
    NSMutableAttributedString *attributedTitle = [[NSMutableAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:frame.size.height * 0.46 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: foreground
    }];
    button.attributedTitle = attributedTitle;
    return button;
}

- (void)stylePopup:(NSPopUpButton *)popup {
    popup.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    popup.contentTintColor = [self primaryTextColor];
    popup.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
}

- (instancetype)initWithModel:(WaterModel *)model finish:(void (^)(void))finish {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 460, 560)
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    self = [super initWithWindow:window];
    if (!self) { return nil; }
    self.model = model;
    self.finishHandler = finish;
    window.opaque = NO;
    window.backgroundColor = NSColor.clearColor;
    window.hasShadow = NO;
    window.movableByWindowBackground = YES;
    window.releasedWhenClosed = NO;
    window.contentView.superview.wantsLayer = YES;
    window.contentView.superview.layer.masksToBounds = NO;
    [self showWelcomePageAnimated:NO];
    return self;
}

- (void)replaceContentWithView:(NSView *)view animated:(BOOL)animated {
    if (!animated || !self.containerView) {
        self.window.contentView = view;
        self.containerView = view;
        return;
    }

    NSView *oldView = self.containerView;
    view.alphaValue = 0;
    self.window.contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 460, 560)];
    [self.window.contentView addSubview:oldView];
    [self.window.contentView addSubview:view];
    self.containerView = view;

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.34;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        oldView.animator.alphaValue = 0;
        view.animator.alphaValue = 1;
    } completionHandler:^{
        self.window.contentView = view;
        self.containerView = view;
    }];
}

- (void)showWelcomePageAnimated:(BOOL)animated {
    self.pageIndex = 0;
    NSView *view = [self pageView];

    CupView *cupView = [[CupView alloc] initWithModel:self.model];
    cupView.displayProgressOverride = 0.75;
    cupView.frame = NSMakeRect(165, 330, 130, 170);
    [view addSubview:cupView];

    NSTextField *title = [self labelWithFrame:NSMakeRect(40, 282, 380, 34) font:[NSFont systemFontOfSize:28 weight:NSFontWeightBold] color:[self primaryTextColor] alignment:NSTextAlignmentCenter];
    title.stringValue = @"欢迎使用 牛马补水站";
    [view addSubview:title];

    NSTextField *subtitle = [self labelWithFrame:NSMakeRect(54, 236, 352, 44) font:[NSFont systemFontOfSize:15] color:[self secondaryTextColor] alignment:NSTextAlignmentCenter];
    subtitle.maximumNumberOfLines = 2;
    subtitle.stringValue = @"工作很重要，身体也值得被温柔提醒。\n先花十秒，把喝水节奏调成适合你的样子。";
    [view addSubview:subtitle];

    NSTextField *maker = [self labelWithFrame:NSMakeRect(28, 24, 320, 58) font:[NSFont systemFontOfSize:11] color:[self secondaryTextColor] alignment:NSTextAlignmentLeft];
    maker.maximumNumberOfLines = 3;
    maker.stringValue = @"制作人 nickzheng1994\nGitHub: https://github.com/nickzheng1994\n邮件: 853717893@qq.com";
    [view addSubview:maker];

    NSButton *next = [self roundButtonWithTitle:@"→" frame:NSMakeRect(382, 28, 48, 48) action:@selector(nextFromWelcome:)];
    [view addSubview:next];

    [self replaceContentWithView:view animated:animated];
}

- (void)showSettingsPageAnimated:(BOOL)animated {
    self.pageIndex = 1;
    NSView *view = [self pageView];

    NSTextField *title = [self labelWithFrame:NSMakeRect(38, 488, 384, 30) font:[NSFont systemFontOfSize:24 weight:NSFontWeightBold] color:[self primaryTextColor] alignment:NSTextAlignmentCenter];
    title.stringValue = @"设置你的喝水计划";
    [view addSubview:title];

    NSTextField *timeLabel = [self labelWithFrame:NSMakeRect(54, 424, 120, 24) font:[NSFont systemFontOfSize:14 weight:NSFontWeightSemibold] color:[self primaryTextColor] alignment:NSTextAlignmentLeft];
    timeLabel.stringValue = @"工作时间";
    [view addSubview:timeLabel];

    self.startPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, 420, 92, 30)];
    [self stylePopup:self.startPopup];
    for (NSInteger i = 0; i < 24; i++) {
        [self.startPopup addItemWithTitle:[NSString stringWithFormat:@"%02ld:00", i]];
    }
    [self.startPopup selectItemAtIndex:self.model.startHour];
    [view addSubview:self.startPopup];

    NSTextField *toLabel = [self labelWithFrame:NSMakeRect(252, 425, 24, 20) font:[NSFont systemFontOfSize:13] color:[self secondaryTextColor] alignment:NSTextAlignmentCenter];
    toLabel.stringValue = @"到";
    [view addSubview:toLabel];

    self.endPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(286, 420, 96, 30)];
    [self stylePopup:self.endPopup];
    for (NSInteger i = 1; i <= 48; i++) {
        NSInteger totalMinutes = i * 30;
        [self.endPopup addItemWithTitle:[NSString stringWithFormat:@"%02ld:%02ld", totalMinutes / 60, totalMinutes % 60]];
    }
    NSInteger endIndex = self.model.endHour * 2 + (self.model.endMinute >= 30 ? 1 : 0) - 1;
    [self.endPopup selectItemAtIndex:MAX(0, MIN(47, endIndex))];
    [view addSubview:self.endPopup];

    NSTextField *intervalLabel = [self labelWithFrame:NSMakeRect(54, 358, 120, 24) font:[NSFont systemFontOfSize:14 weight:NSFontWeightSemibold] color:[self primaryTextColor] alignment:NSTextAlignmentLeft];
    intervalLabel.stringValue = @"提醒间隔";
    [view addSubview:intervalLabel];

    self.intervalPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, 354, 232, 30)];
    [self stylePopup:self.intervalPopup];
    [self.intervalPopup addItemWithTitle:@"15 分钟"];
    [self.intervalPopup addItemWithTitle:@"30 分钟"];
    [self.intervalPopup addItemWithTitle:@"60 分钟"];
    NSInteger selectedIntervalIndex = self.model.reminderIntervalMinutes == 15 ? 0 : (self.model.reminderIntervalMinutes == 30 ? 1 : 2);
    [self.intervalPopup selectItemAtIndex:selectedIntervalIndex];
    [view addSubview:self.intervalPopup];

    NSTextField *lunchLabel = [self labelWithFrame:NSMakeRect(54, 318, 120, 24) font:[NSFont systemFontOfSize:14 weight:NSFontWeightSemibold] color:[self primaryTextColor] alignment:NSTextAlignmentLeft];
    lunchLabel.stringValue = @"午休时间";
    [view addSubview:lunchLabel];

    self.lunchStartPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, 314, 92, 30)];
    self.lunchEndPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(286, 314, 96, 30)];
    [self stylePopup:self.lunchStartPopup];
    [self stylePopup:self.lunchEndPopup];
    for (NSInteger i = 0; i <= 48; i++) {
        NSInteger totalMinutes = i * 30;
        [self.lunchStartPopup addItemWithTitle:[NSString stringWithFormat:@"%02ld:%02ld", totalMinutes / 60, totalMinutes % 60]];
        [self.lunchEndPopup addItemWithTitle:[NSString stringWithFormat:@"%02ld:%02ld", totalMinutes / 60, totalMinutes % 60]];
    }
    NSInteger lunchStartIndex = self.model.lunchStartHour * 2 + (self.model.lunchStartMinute >= 30 ? 1 : 0);
    NSInteger lunchEndIndex = self.model.lunchEndHour * 2 + (self.model.lunchEndMinute >= 30 ? 1 : 0);
    [self.lunchStartPopup selectItemAtIndex:MAX(0, MIN(48, lunchStartIndex))];
    [self.lunchEndPopup selectItemAtIndex:MAX(0, MIN(48, lunchEndIndex))];
    [view addSubview:self.lunchStartPopup];
    [view addSubview:self.lunchEndPopup];

    NSTextField *lunchToLabel = [self labelWithFrame:NSMakeRect(252, 319, 24, 20) font:[NSFont systemFontOfSize:13] color:[self secondaryTextColor] alignment:NSTextAlignmentCenter];
    lunchToLabel.stringValue = @"到";
    [view addSubview:lunchToLabel];

    NSTextField *targetTitle = [self labelWithFrame:NSMakeRect(54, 270, 160, 24) font:[NSFont systemFontOfSize:14 weight:NSFontWeightSemibold] color:[self primaryTextColor] alignment:NSTextAlignmentLeft];
    targetTitle.stringValue = @"每日喝水目标";
    [view addSubview:targetTitle];

    self.targetLabel = [self labelWithFrame:NSMakeRect(272, 270, 110, 24) font:[NSFont monospacedDigitSystemFontOfSize:14 weight:NSFontWeightSemibold] color:[self primaryTextColor] alignment:NSTextAlignmentRight];
    [view addSubview:self.targetLabel];

    self.targetSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(54, 228, 328, 26)];
    self.targetSlider.minValue = 500;
    self.targetSlider.maxValue = kDailyTargetMaxMl;
    self.targetSlider.numberOfTickMarks = 46;
    self.targetSlider.allowsTickMarkValuesOnly = YES;
    self.targetSlider.target = self;
    self.targetSlider.action = @selector(targetChanged:);
    self.targetSlider.integerValue = self.model.dailyTargetMl;
    [view addSubview:self.targetSlider];
    [self updateTargetLabel];

    NSTextField *hint = [self labelWithFrame:NSMakeRect(54, 178, 328, 40) font:[NSFont systemFontOfSize:12] color:[self secondaryTextColor] alignment:NSTextAlignmentCenter];
    hint.maximumNumberOfLines = 2;
    hint.stringValue = @"默认 2000 ml，最高 5000 ml。\n拖动滑块，找到你今天想认真完成的小目标。";
    [view addSubview:hint];

    NSButton *confirm = [self buttonWithTitle:@"确定" frame:NSMakeRect(170, 86, 120, 40) action:@selector(confirmSettings:)];
    confirm.bezelStyle = NSBezelStyleRegularSquare;
    [view addSubview:confirm];

    [self replaceContentWithView:view animated:animated];
}

- (void)showCompletePageAnimated:(BOOL)animated {
    self.pageIndex = 2;
    NSView *view = [self pageView];

    NSTextField *title = [self labelWithFrame:NSMakeRect(40, 490, 380, 30) font:[NSFont systemFontOfSize:24 weight:NSFontWeightBold] color:[self primaryTextColor] alignment:NSTextAlignmentCenter];
    title.stringValue = @"设置完成";
    [view addSubview:title];

    NSTextField *topArrow = [self labelWithFrame:NSMakeRect(350, 542, 72, 62) font:[NSFont systemFontOfSize:54 weight:NSFontWeightBold] color:[NSColor colorWithCalibratedRed:0.08 green:0.36 blue:0.72 alpha:0.92] alignment:NSTextAlignmentCenter];
    topArrow.stringValue = @"↑";
    [view addSubview:topArrow];

    NSTextField *topTip = [self labelWithFrame:NSMakeRect(246, 470, 176, 34) font:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium] color:[self secondaryTextColor] alignment:NSTextAlignmentCenter];
    topTip.maximumNumberOfLines = 2;
    topTip.stringValue = @"之后可以从顶部图标\n实时查看喝水情况";
    [view addSubview:topTip];

    OnboardingBubblesView *bubblesView = [[OnboardingBubblesView alloc] initWithFrame:NSMakeRect(80, 186, 300, 292)];
    [view addSubview:bubblesView];

    NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(95, 202, 270, 270)];
    imageView.image = [self imageNamedFromBundle:@"OnboardingCoach" extension:@"png"];
    imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [view addSubview:imageView];

    NSTextField *copy = [self labelWithFrame:NSMakeRect(52, 138, 356, 46) font:[NSFont systemFontOfSize:15 weight:NSFontWeightMedium] color:[self primaryTextColor] alignment:NSTextAlignmentCenter];
    copy.maximumNumberOfLines = 2;
    copy.stringValue = @"努力工作的同时，也要记得喝水。\n你负责发光，牛马补水站负责轻轻提醒。";
    [view addSubview:copy];

    NSButton *start = [self buttonWithTitle:@"开始使用" frame:NSMakeRect(166, 54, 128, 40) action:@selector(finishOnboarding:)];
    start.bezelStyle = NSBezelStyleRegularSquare;
    [view addSubview:start];

    [self replaceContentWithView:view animated:animated];
}

- (NSView *)pageView {
    NSVisualEffectView *view = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 460, 560)];
    view.material = NSVisualEffectMaterialHUDWindow;
    view.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    view.state = NSVisualEffectStateActive;
    view.wantsLayer = YES;
    view.layer.cornerRadius = 32;
    view.layer.masksToBounds = YES;

    NSView *glassTint = [[NSView alloc] initWithFrame:view.bounds];
    glassTint.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    glassTint.wantsLayer = YES;
    glassTint.layer.backgroundColor = [NSColor colorWithCalibratedWhite:1 alpha:0.72].CGColor;
    glassTint.layer.cornerRadius = 32;
    [view addSubview:glassTint positioned:NSWindowBelow relativeTo:nil];

    NSView *highlight = [[NSView alloc] initWithFrame:NSInsetRect(view.bounds, 1, 1)];
    highlight.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    highlight.wantsLayer = YES;
    highlight.layer.borderWidth = 0;
    highlight.layer.backgroundColor = [NSColor colorWithCalibratedWhite:1 alpha:0.10].CGColor;
    highlight.layer.cornerRadius = 31;
    [view addSubview:highlight positioned:NSWindowBelow relativeTo:nil];

    NSButton *close = [self pillButtonWithTitle:@"×"
                                          frame:NSMakeRect(22, 514, 28, 28)
                                     background:[NSColor colorWithCalibratedWhite:1 alpha:0.64]
                                     foreground:[NSColor colorWithCalibratedWhite:0.15 alpha:1]
                                         action:@selector(closeOnboarding:)];
    [view addSubview:close];
    return view;
}

- (NSTextField *)labelWithFrame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color alignment:(NSTextAlignment)alignment {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.font = font;
    label.textColor = color;
    label.alignment = alignment;
    return label;
}

- (NSButton *)buttonWithTitle:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.target = self;
    button.action = action;
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    button.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    button.contentTintColor = [self primaryTextColor];
    button.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: button.font,
        NSForegroundColorAttributeName: [self primaryTextColor]
    }];
    return button;
}

- (NSButton *)roundButtonWithTitle:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    return [self pillButtonWithTitle:title
                               frame:frame
                          background:NSColor.blackColor
                          foreground:NSColor.whiteColor
                              action:action];
}

- (NSImage *)imageNamedFromBundle:(NSString *)name extension:(NSString *)extension {
    NSString *path = [NSBundle.mainBundle pathForResource:name ofType:extension];
    return path ? [[NSImage alloc] initWithContentsOfFile:path] : nil;
}

- (void)updateTargetLabel {
    self.targetLabel.stringValue = [NSString stringWithFormat:@"%ld ml", self.targetSlider.integerValue];
}

- (void)nextFromWelcome:(id)sender {
    [self showSettingsPageAnimated:YES];
}

- (void)closeOnboarding:(id)sender {
    [NSApp terminate:nil];
}

- (void)targetChanged:(id)sender {
    NSInteger rounded = (NSInteger)llround((double)self.targetSlider.integerValue / 100.0) * 100;
    self.targetSlider.integerValue = rounded;
    [self updateTargetLabel];
}

- (void)confirmSettings:(id)sender {
    NSInteger endTotalMinutes = (self.endPopup.indexOfSelectedItem + 1) * 30;
    NSInteger lunchStartMinutes = self.lunchStartPopup.indexOfSelectedItem * 30;
    NSInteger lunchEndMinutes = self.lunchEndPopup.indexOfSelectedItem * 30;
    NSInteger intervals[] = {15, 30, 60};
    NSInteger intervalIndex = MAX(0, MIN(2, self.intervalPopup.indexOfSelectedItem));
    [self.model updateWorkStartHour:self.startPopup.indexOfSelectedItem
                             endHour:endTotalMinutes / 60
                           endMinute:endTotalMinutes % 60];
    [self.model updateLunchStartHour:lunchStartMinutes / 60
                          startMinute:lunchStartMinutes % 60
                              endHour:lunchEndMinutes / 60
                            endMinute:lunchEndMinutes % 60];
    [self.model updateReminderIntervalMinutes:intervals[intervalIndex]];
    [self.model updateDailyTargetMl:self.targetSlider.integerValue];
    [self showCompletePageAnimated:YES];
}

- (void)finishOnboarding:(id)sender {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:kOnboardingComplete];
    [NSUserDefaults.standardUserDefaults synchronize];
    if (self.finishHandler) { self.finishHandler(); }
    [self close];
}

@end

@interface ReminderController : NSObject
@property (nonatomic, strong) WaterModel *model;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSTimer *summaryTimer;
@property (nonatomic, strong) NSTimer *chargeTimer;
@property (weak) AppDelegate *appDelegate;
- (instancetype)initWithModel:(WaterModel *)model appDelegate:(AppDelegate *)appDelegate;
- (void)start;
- (void)scheduleNextTimer;
- (void)scheduleSummaryTimer;
- (void)scheduleChargeTimer;
- (void)snoozeFiveMinutes;
- (void)triggerTestReminder;
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSPopover *popover;
@property (nonatomic, strong) WaterModel *model;
@property (nonatomic, strong) PanelController *panelController;
@property (nonatomic, strong) ReminderWindowController *reminderWindowController;
@property (nonatomic, strong) SummaryWindowController *summaryWindowController;
@property (nonatomic, strong) PhoneChargeWindowController *phoneChargeWindowController;
@property (nonatomic, strong) OnboardingWindowController *onboardingWindowController;
@property (nonatomic, strong) ReminderController *reminderController;
@property (nonatomic, strong) NSTimer *attentionTimer;
@property (nonatomic) BOOL attentionOn;
- (void)showPopover;
- (void)showReminderWindow;
- (void)showSummaryWindow;
- (void)showPhoneChargeWindow;
- (void)showOnboardingIfNeeded;
- (void)startReminderTimers;
- (void)setNeedsAttention:(BOOL)needsAttention;
@end

@implementation ReminderController

- (instancetype)initWithModel:(WaterModel *)model appDelegate:(AppDelegate *)appDelegate {
    self = [super init];
    if (!self) { return nil; }
    self.model = model;
    self.appDelegate = appDelegate;
    return self;
}

- (void)start {
    [self scheduleNextTimer];
    [self scheduleSummaryTimer];
    [self scheduleChargeTimer];
}

- (void)scheduleNextTimer {
    [self.timer invalidate];
    [self.model resetIfNeeded];
    [self.model recompute];
    NSDate *next = [self.model nextReminderDate];
    NSTimeInterval interval = MAX(1, next.timeIntervalSinceNow);
    self.timer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(fireReminder) userInfo:nil repeats:NO];
    [self.appDelegate.panelController refresh];
}

- (void)scheduleSummaryTimer {
    [self.summaryTimer invalidate];
    NSDate *next = [self nextSummaryDate];
    NSTimeInterval interval = MAX(1, next.timeIntervalSinceNow);
    self.summaryTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(fireSummaryReminder) userInfo:nil repeats:NO];
}

- (void)scheduleChargeTimer {
    [self.chargeTimer invalidate];
    NSDate *next = [self nextChargeDate];
    NSTimeInterval interval = MAX(1, next.timeIntervalSinceNow);
    self.chargeTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(fireChargeReminder) userInfo:nil repeats:NO];
}

- (void)snoozeFiveMinutes {
    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:5 * 60 target:self selector:@selector(fireReminder) userInfo:nil repeats:NO];
    [self.appDelegate setNeedsAttention:YES];
}

- (void)triggerTestReminder {
    NSLog(@"WaterReminder test reminder triggered");
    [self.model resetIfNeeded];
    [self.model recompute];
    [self.appDelegate setNeedsAttention:YES];
    [self.appDelegate showReminderWindow];
}

- (void)fireReminder {
    [self.model resetIfNeeded];
    [self.model recompute];
    [self.appDelegate setNeedsAttention:YES];
    [self.appDelegate showReminderWindow];
    [self scheduleNextTimer];
}

- (void)fireSummaryReminder {
    [self.model resetIfNeeded];
    [self.model recompute];
    [self.appDelegate setNeedsAttention:YES];
    [self.appDelegate showSummaryWindow];
    [self scheduleSummaryTimer];
}

- (void)fireChargeReminder {
    [self.model resetIfNeeded];
    [self.model recompute];
    [self.appDelegate setNeedsAttention:YES];
    [self.appDelegate showPhoneChargeWindow];
    [self scheduleChargeTimer];
}

- (NSDate *)nextSummaryDate {
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDate *now = [NSDate date];
    NSDateComponents *parts = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:now];
    parts.hour = self.model.endHour;
    parts.minute = self.model.endMinute;
    parts.second = 0;

    NSDate *todaySummary = [calendar dateFromComponents:parts];
    if ([todaySummary compare:now] == NSOrderedDescending) {
        return todaySummary;
    }

    NSDate *tomorrow = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:now options:0];
    NSDateComponents *tomorrowParts = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:tomorrow];
    tomorrowParts.hour = self.model.endHour;
    tomorrowParts.minute = self.model.endMinute;
    tomorrowParts.second = 0;
    return [calendar dateFromComponents:tomorrowParts];
}

- (NSDate *)nextChargeDate {
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDate *now = [NSDate date];
    NSDateComponents *parts = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:now];
    parts.hour = self.model.endHour;
    parts.minute = self.model.endMinute;
    parts.second = 0;

    NSDate *todayEnd = [calendar dateFromComponents:parts];
    NSDate *todayCharge = [calendar dateByAddingUnit:NSCalendarUnitMinute value:-30 toDate:todayEnd options:0];
    if ([todayCharge compare:now] == NSOrderedDescending) {
        return todayCharge;
    }

    NSDate *tomorrow = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:now options:0];
    NSDateComponents *tomorrowParts = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:tomorrow];
    tomorrowParts.hour = self.model.endHour;
    tomorrowParts.minute = self.model.endMinute;
    tomorrowParts.second = 0;
    NSDate *tomorrowEnd = [calendar dateFromComponents:tomorrowParts];
    return [calendar dateByAddingUnit:NSCalendarUnitMinute value:-30 toDate:tomorrowEnd options:0];
}

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.model = [WaterModel new];
    [self configureStatusItem];
    [self configurePopover];
    self.reminderController = [[ReminderController alloc] initWithModel:self.model appDelegate:self];
    [self showOnboardingIfNeeded];

    if ([NSProcessInfo.processInfo.arguments containsObject:@"--test-reminder"]) {
        [self.reminderController performSelector:@selector(triggerTestReminder) withObject:nil afterDelay:1.0];
    }
}

- (void)startReminderTimers {
    [self.reminderController start];
}

- (void)showOnboardingIfNeeded {
    if ([NSUserDefaults.standardUserDefaults boolForKey:kOnboardingComplete]) {
        [self startReminderTimers];
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.onboardingWindowController = [[OnboardingWindowController alloc] initWithModel:self.model finish:^{
        [weakSelf.panelController refresh];
        [weakSelf startReminderTimers];
        weakSelf.onboardingWindowController = nil;
    }];
    [self.onboardingWindowController showWindow:nil];
    [self.onboardingWindowController.window center];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)configureStatusItem {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(togglePopover:);
    [self updateStatusIcon:NO];
}

- (void)configurePopover {
    self.popover = [NSPopover new];
    self.popover.behavior = NSPopoverBehaviorTransient;
    self.popover.contentSize = NSMakeSize(340, 610);
    __weak typeof(self) weakSelf = self;
    self.panelController = [[PanelController alloc] initWithModel:self.model settings:^{
        [weakSelf.reminderController scheduleNextTimer];
        [weakSelf.reminderController scheduleSummaryTimer];
        [weakSelf.reminderController scheduleChargeTimer];
    } test:^{
        [weakSelf.reminderController triggerTestReminder];
    }];
    self.popover.contentViewController = self.panelController;
}

- (void)showReminderWindow {
    NSLog(@"WaterReminder reminder window requested");
    if (!self.reminderWindowController) {
        __weak typeof(self) weakSelf = self;
        self.reminderWindowController = [[ReminderWindowController alloc] initWithModel:self.model drink:^(NSInteger amount) {
            [weakSelf.model recordDrinkAmount:amount];
            [weakSelf setNeedsAttention:NO];
            [weakSelf.panelController refresh];
            [weakSelf.reminderController scheduleNextTimer];
        } snooze:^{
            [weakSelf.reminderController snoozeFiveMinutes];
        }];
    }

    [self.reminderWindowController refresh];
    [self.reminderWindowController showWindow:nil];
    [self.reminderWindowController.window center];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showSummaryWindow {
    if (!self.summaryWindowController) {
        self.summaryWindowController = [[SummaryWindowController alloc] initWithModel:self.model];
    }
    [self.summaryWindowController refresh];
    [self.summaryWindowController showWindow:nil];
    [self.summaryWindowController.window center];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showPhoneChargeWindow {
    if (!self.phoneChargeWindowController) {
        self.phoneChargeWindowController = [[PhoneChargeWindowController alloc] init];
    }
    [self.phoneChargeWindowController showWindow:nil];
    [self.phoneChargeWindowController.window center];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showPopover {
    NSStatusBarButton *button = self.statusItem.button;
    if (!button) { return; }
    [self setNeedsAttention:NO];
    [self.panelController refresh];
    if (self.popover.isShown) {
        [self.popover performClose:nil];
    } else {
        [self.popover showRelativeToRect:button.bounds ofView:button preferredEdge:NSRectEdgeMinY];
        [NSApp activateIgnoringOtherApps:YES];
    }
}

- (void)setNeedsAttention:(BOOL)needsAttention {
    [self.attentionTimer invalidate];
    self.attentionTimer = nil;
    self.attentionOn = NO;
    [self updateStatusIcon:needsAttention];
    if (!needsAttention) { return; }
    self.attentionTimer = [NSTimer scheduledTimerWithTimeInterval:0.8 repeats:YES block:^(NSTimer * _Nonnull timer) {
        self.attentionOn = !self.attentionOn;
        [self updateStatusIcon:self.attentionOn];
    }];
}

- (void)updateStatusIcon:(BOOL)alerting {
    NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightSemibold];
    NSString *symbol = alerting ? @"drop.fill" : @"drop";
    NSImage *image = [[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:@"牛马补水站"] imageWithSymbolConfiguration:config];
    self.statusItem.button.image = image;
    self.statusItem.button.title = alerting ? @" 喝水" : @"";
}

- (void)togglePopover:(id)sender {
    [self showPopover];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSArray<NSRunningApplication *> *runningApps = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.ehousechina.drinktime"];
        pid_t currentPID = getpid();
        for (NSRunningApplication *runningApp in runningApps) {
            if (runningApp.processIdentifier != currentPID) {
                return 0;
            }
        }

        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
