//
//  SENService.m
//  Pods
//
//  Created by Jimmy Lu on 9/10/14.
//
//
#import <UIKit/UIKit.h>
#import "SENService.h"

@implementation SENService

- (id)init {
    self = [super init];
    if (self) {
        [self listenForAppEvents];
    }
    return self;
}

- (void)listenForAppEvents {
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(serviceBecameActive)
                   name:UIApplicationDidBecomeActiveNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(serviceWillBecomeInactive)
                   name:UIApplicationWillResignActiveNotification
                 object:nil];
}

- (void)serviceBecameActive {}
- (void)serviceWillBecomeInactive {}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end