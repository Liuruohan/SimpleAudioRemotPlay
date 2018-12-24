//
//  LHAudioPlayer.h
//  AudioAndVideoReader
//
//  Created by cntapple1 on 2018/12/20.
//  Copyright © 2018 cntapple1. All rights reserved.
//

#import <Foundation/Foundation.h>



@interface LHAudioPlayer : NSObject

- (instancetype)initWithUrlString:(NSString*)urlString;

- (void)play;

- (void)pause;

@property (nonatomic, readonly, getter=isStoped) BOOL stoped;

@end


