// Feeds picks (a file, one emoji per line) to Apple's Frequently Used code, EmojiFoundation's EMFEmojiPreferences, and
// prints its list. Runs in the iOS simulator: Tools/emoji/apple_frequent.py builds it and gives it the tests' picks (D68).
// Args: picks file, count shown, and any third argument to prune old picks after each pick, as saving does.
#import <Foundation/Foundation.h>
#include <dlfcn.h>
@interface EMFEmojiToken : NSObject
+ (id)emojiTokenWithString:(NSString *)s localeData:(id)ld;
- (NSString *)string;
@end
@interface EMFEmojiPreferences : NSObject
- (void)didUseEmoji:(id)token usageMode:(NSString *)mode;
- (NSArray *)recentEmojis;
- (NSArray *)recentEmojisByFillingWithPrepopulatedEmojisUpTo:(NSUInteger)n;
- (void)resetEmojiDefaults;
- (double)scoreForEmojiString:(NSString *)s;
- (void)readEmojiDefaults;
- (void)_pruneOldestEmojiUsageFromHistory;
@end
int main(int argc, const char **argv) {
    @autoreleasepool {
        void *h = dlopen("/System/Library/PrivateFrameworks/EmojiFoundation.framework/EmojiFoundation", RTLD_NOW);
        if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 1; }
        NSString *mode = *(NSString * __strong *)dlsym(h, "EMFEmojiUsageKeyboard");
        Class P = NSClassFromString(@"EMFEmojiPreferences"), T = NSClassFromString(@"EMFEmojiToken");
        EMFEmojiPreferences *p = [P new];
        [p resetEmojiDefaults];
        NSString *seq = [NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:nil];
        for (NSString *e in [seq componentsSeparatedByString:@"\n"]) {
            if (e.length == 0) continue;
            [p didUseEmoji:[T emojiTokenWithString:e localeData:nil] usageMode:mode];
            // what saving does first (writeEmojiDefaultsThreadSafeAndNotify:): past 1,000 picks keep the last 500. Saving
            // itself in this loop reloads the defaults in the background and loses picks, so it's called alone.
            if (argc > 3) [p _pruneOldestEmojiUsageFromHistory];
        }
        NSUInteger n = argc > 2 ? atoi(argv[2]) : 30;
        NSMutableArray *out = [NSMutableArray array];
        for (EMFEmojiToken *t in [p recentEmojis]) [out addObject:[t string]];
        printf("recents(%lu): %s\n", (unsigned long)out.count, [[out componentsJoinedByString:@" "] UTF8String]);
        [out removeAllObjects];
        for (EMFEmojiToken *t in [p recentEmojisByFillingWithPrepopulatedEmojisUpTo:n]) [out addObject:[t string]];
        printf("shown(%lu): %s\n", (unsigned long)out.count, [[out componentsJoinedByString:@" "] UTF8String]);
    }
    return 0;
}
