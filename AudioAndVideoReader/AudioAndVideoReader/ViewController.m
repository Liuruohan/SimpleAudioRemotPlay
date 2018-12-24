//
//  ViewController.m
//  AudioAndVideoReader
//
//  Created by cntapple1 on 2018/12/20.
//  Copyright © 2018 cntapple1. All rights reserved.
//

#import "ViewController.h"
#import "LHAudioPlayer.h"

@interface ViewController ()

@property (nonatomic, strong)LHAudioPlayer * player;


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.player = [[LHAudioPlayer alloc] initWithUrlString:@"https://zonble.net/MIDI/orz.mp3"];
}

- (IBAction)playButtonClick:(UIButton *)sender {
    sender.selected = !sender.selected;
    if (sender.selected) {
        [self.player play];
    }else{
        [self.player pause];
    }
}

@end
