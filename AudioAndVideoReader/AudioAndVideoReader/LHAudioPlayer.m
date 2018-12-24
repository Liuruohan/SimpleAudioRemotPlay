//
//  LHAudioPlayer.m
//  AudioAndVideoReader
//
//  Created by cntapple1 on 2018/12/20.
//  Copyright © 2018 cntapple1. All rights reserved.
//

#import "LHAudioPlayer.h"
#import <AudioToolbox/AudioToolbox.h>

//声明的callback
//监听属性获取的callback方法
static void LHAudioFileStreamPropertyListener(
                                              void *                            inClientData,
                                              AudioFileStreamID                inAudioFileStream,
                                              AudioFileStreamPropertyID        inPropertyID,
                                              AudioFileStreamPropertyFlags *    ioFlags);
//监听Packet的callback方法
static void LHAudioFileStreamPacketsCallback(
                                             void *                            inClientData,
                                             UInt32                            inNumberBytes,
                                             UInt32                            inNumberPackets,
                                             const void *                    inInputData,
                                             AudioStreamPacketDescription    *inPacketDescriptions);
static void LHAudioQueueOutputCallback(
                                       void * __nullable       inUserData,
                                       AudioQueueRef           inAQ,
                                       AudioQueueBufferRef     inBuffer);

static void  LHAudioQueuePropertyListenerProc(
                                void * __nullable       inUserData,
                                AudioQueueRef           inAQ,
                                AudioQueuePropertyID    inID);




@interface LHAudioPlayer ()<NSURLConnectionDataDelegate>{
    struct{
        BOOL stopped;
        BOOL loaded;
    }playerStates;
    NSMutableArray * packages;
    AudioFileStreamID audiofileStremaId;
    NSURLConnection * connection;
    AudioStreamBasicDescription streamDescription;
    AudioQueueRef outputQueue;
    size_t readHead;  //读取的位置
}

@end

@implementation LHAudioPlayer

- (instancetype)initWithUrlString:(NSString*)urlString{
    if (self = [super init]) {
        playerStates.stopped = NO;
        //初始化包数组。
        packages = [NSMutableArray arrayWithCapacity:0];
        //第一步：建立audio parser，指定callback ，以及建立http链接，
        AudioFileStreamOpen((__bridge  void * _Nullable)self, LHAudioFileStreamPropertyListener, LHAudioFileStreamPacketsCallback, kAudioFileMP3Type, &audiofileStremaId);
        //创建connection
       connection = [[NSURLConnection alloc] initWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlString]] delegate:self];
    }
    return self;
}
- (void)play{
    //播放的audio queue（音频队列）开始播放
    AudioQueueStart(outputQueue, NULL);
}
- (void)pause{
    //播放的audio queue（音频队列）暂停
    AudioQueuePause(outputQueue);
}
- (BOOL)isStoped{
    return playerStates.stopped;
}
- (double)packetsPerSecond{
    if (streamDescription.mFramesPerPacket) {
        //一个包中的帧率 * 一秒的包数 = 采样率（每秒帧数）。
        return streamDescription.mSampleRate/streamDescription.mFramesPerPacket;
    }
    return 44100.0/1152.0; //通用值
}
#pragma mark -
#pragma mark NSURLConnectionDataDelegate
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response{
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        if ([(NSHTTPURLResponse*)response statusCode] != 200) {
            [connection cancel];
            playerStates.stopped = YES;
        }
    }
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data{
    //第二步：抓到了部分档案，交由audio parser开始parse 出 data
    //只有在传入data之后，LHAudioFileStreamPropertyListener和LHAudioFileStreamPacketsCallback函数才会相应，因为有数据已经可以parse
    //每次传入一个data，LHAudioFileStreamPacketsCallback函数会响应两次（第一次传入data相应一次）。在第一次传入data时LHAudioFileStreamPropertyListener会响应几次，获取音频属性。
    AudioFileStreamParseBytes(audiofileStremaId, (UInt32)[data length], [data bytes], 0);
}
- (void)connectionDidFinishLoading:(NSURLConnection *)connection{
    NSLog(@"Complete loading data");
    playerStates.loaded = YES;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error{
    NSLog(@"Failed to load data: %@", [error localizedDescription]);
    playerStates.stopped = YES;
}
#pragma mark -
#pragma mark Audio Parser and Audio Queue callbacks
- (void)_enqueueDataWithPacketsCount:(size_t)inPacketCount{
    //audio Queue 没有建立
    if (!outputQueue) {
        return;
    }
    if (readHead == [packages count]) {
        // 第六步：已經把所有 packet 都播完了，檔案播放結束。
        if (playerStates.loaded) {
            AudioQueueStop(outputQueue, false);
            playerStates.stopped = YES;
            return;
        }
    }
    //当前读取位置+需要读取的个数大于等于package的个数，重新计算inPacketCount。如果小于，说明要读取得inPacketCount已经加载完毕
    if (readHead + inPacketCount >= [packages count]) {
        inPacketCount = [packages count] - readHead;
    }
    UInt32 totalSize = 0;
    UInt32 index;
    
    for (index = 0 ; index < inPacketCount ; index++) {
        NSData *packet = packages[index + readHead];
        totalSize += packet.length;
    }
    //根据size分配对应的outbufferQueue的缓存
    OSStatus status = 0;
    AudioQueueBufferRef buffer;
    status = AudioQueueAllocateBuffer(outputQueue, totalSize, &buffer);
    assert(status == noErr);
    buffer->mAudioDataByteSize = totalSize;
    buffer->mUserData = (__bridge void * _Nullable)(self);
    //开辟一个连续的数组类型的堆空间，数组的每个堆内存为AudioStreamPacketDescription长度
    AudioStreamPacketDescription *packetDescs = calloc(inPacketCount,sizeof(AudioStreamPacketDescription));
    totalSize = 0;
    for (index = 0 ; index < inPacketCount; index++) {
        size_t readIndex = index + readHead;
        NSData * packet = packages[readIndex];
        memcpy(buffer->mAudioData + totalSize, packet.bytes, packet.length);
        AudioStreamPacketDescription description;
        description.mStartOffset = totalSize;
        description.mDataByteSize = (UInt32)packet.length;
        description.mVariableFramesInPacket = 0;
        totalSize += packet.length;
        memcpy(&(packetDescs[index]), &description, sizeof(AudioStreamPacketDescription));
    }
    status = AudioQueueEnqueueBuffer(outputQueue, buffer, (UInt32)inPacketCount, packetDescs);
    free(packetDescs);
    readHead += inPacketCount;
}
-(void)_createAudioQueueWithAudioStreamDescription:(AudioStreamBasicDescription*)audioStreamDescription{
    //将函数返回参数复制到对象的全局变量中，方便使用
    memcpy(&streamDescription, audioStreamDescription, sizeof(AudioStreamBasicDescription));
    //创建一个新的Audio Queue的output。
    OSStatus status = AudioQueueNewOutput(audioStreamDescription, LHAudioQueueOutputCallback, (__bridge void * _Nullable)self, CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &outputQueue);
    //打个断点
    assert(status == noErr);
    //监听Audio queue是否正在运行
    status = AudioQueueAddPropertyListener(outputQueue, kAudioQueueProperty_IsRunning, LHAudioQueuePropertyListenerProc, (__bridge void * _Nullable)self);
    //Audio queue初始化
    AudioQueuePrime(outputQueue, 0, NULL);
    
}
- (void)_storePacketsWithNumberOfBytes:(UInt32)inNumberBytes
                       numberOfPackets:(UInt32)inNumberPackets
                             inputData:(const void * )inInputData
                packetDescriptions:(AudioStreamPacketDescription*)packetDescription{
    
    for (UInt32 i = 0; i < inNumberPackets; i++) {
        SInt64 packetStart = packetDescription[i].mStartOffset;
        UInt32 packetSize = packetDescription[i].mDataByteSize;
        assert(packetSize > 0);
        NSData * data = [NSData dataWithBytes:inInputData+packetStart length:packetSize];
        [packages addObject:data];
    }
    //第五步 因为parse出的packet够多，缓冲内容够大，因此可以播放,  这个demo设置缓冲大于3秒就可以播放了。
    //第一次缓存大于三秒后，将package放到buffer，开始播放，之后不再走这个判断，因为readHead大于0；
    if (readHead == 0 && packages.count > (int)([self packetsPerSecond] * 3)) {
        //Audio queue开始运行
        AudioQueueStart(outputQueue, NULL);
        //将这3秒的data加入播放队列。
        [self _enqueueDataWithPacketsCount:(int)[self packetsPerSecond]*3];
    }
    
}

- (void)_audioQueueDidStart{
    NSLog(@"_audioQueueDidStart");
}
- (void)_audioQueueDidStop{
    NSLog(@"_audioQueueDidStop");
    playerStates.stopped = YES;
}
- (void)dealloc{
    AudioQueueReset(outputQueue);
    AudioFileStreamClose(audiofileStremaId);
    [connection cancel];
}
@end

static void LHAudioFileStreamPropertyListener(
                                              void *                            inClientData,
                                              AudioFileStreamID                inAudioFileStream,
                                              AudioFileStreamPropertyID        inPropertyID,
                                              AudioFileStreamPropertyFlags *    ioFlags){
    LHAudioPlayer * player = (__bridge LHAudioPlayer *)inClientData;
    if (inPropertyID == kAudioFileStreamProperty_DataFormat) {
        UInt32 dataSize = 0;
        OSStatus status; //不等于0就表明出错了
        AudioStreamBasicDescription audioStreamDescription;
        Boolean writeable = false;
        //获取了数据大小和是否可写
        status = AudioFileStreamGetPropertyInfo(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &dataSize, &writeable);
        //根据上一层的数据大小传入，获取audioStreamDescription；
        status = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &dataSize, &audioStreamDescription);
        
        NSLog(@"mSampleRate: %f", audioStreamDescription.mSampleRate);
        NSLog(@"mFormatID: %u", audioStreamDescription.mFormatID);
        NSLog(@"mFormatFlags: %u", audioStreamDescription.mFormatFlags);
        NSLog(@"mBytesPerPacket: %u", audioStreamDescription.mBytesPerPacket);
        NSLog(@"mFramesPerPacket: %u", audioStreamDescription.mFramesPerPacket);
        NSLog(@"mBytesPerFrame: %u", audioStreamDescription.mBytesPerFrame);
        NSLog(@"mChannelsPerFrame: %u", audioStreamDescription.mChannelsPerFrame);
        NSLog(@"mBitsPerChannel: %u", audioStreamDescription.mBitsPerChannel);
        NSLog(@"mReserved: %u", audioStreamDescription.mReserved);
        
        //第三步：Audio parser成功parse出audio档案格式，我们根据档案格式资讯，建立 Audio Queue ，同时监听Audio Queue是否正在执行
        [player _createAudioQueueWithAudioStreamDescription:&audioStreamDescription];
    }
    
}
static void LHAudioFileStreamPacketsCallback(
                                             void *                            inClientData,
                                             UInt32                            inNumberBytes,
                                             UInt32                            inNumberPackets,
                                             const void *                    inInputData,
                                             AudioStreamPacketDescription    *inPacketDescriptions){
    //第四步：audio Parser成功parse 出packets，我们将这些资料存储起来。（此函数会频繁响应）
    LHAudioPlayer * player = (__bridge LHAudioPlayer *)inClientData;
    [player _storePacketsWithNumberOfBytes:inNumberBytes numberOfPackets:inNumberPackets inputData:inInputData packetDescriptions:inPacketDescriptions];
    
}
//在Audio Queue资料快播完的时候呼出
static void LHAudioQueueOutputCallback(
                                       void * __nullable       inUserData,
                                       AudioQueueRef           inAQ,
                                       AudioQueueBufferRef     inBuffer){
    //由于在enqueue中每次都创建了新的buffer，所以在这里需要freebuffer，可以模仿苹果的demo，创建三个buffer，循环使用（复用）。
    AudioQueueFreeBuffer(inAQ, inBuffer);
    LHAudioPlayer * player = (__bridge LHAudioPlayer *)inUserData;
    //在这里设置了每个buffer读取5秒的packet，所以一般每隔5秒回调用一下该函数。
    [player _enqueueDataWithPacketsCount:(int)([player packetsPerSecond] * 5)];
}
//Audio Queue状态改变时会调用
static void  LHAudioQueuePropertyListenerProc(
                                              void * __nullable       inUserData,
                                              AudioQueueRef           inAQ,
                                              AudioQueuePropertyID    inID){
    LHAudioPlayer * player = (__bridge LHAudioPlayer *)inUserData;
    UInt32 dataSize;
    OSStatus status = 0;
    status = AudioQueueGetPropertySize(inAQ, inID, &dataSize);
    if (inID == kAudioQueueProperty_IsRunning) {
        UInt32 running;
        status = AudioQueueGetProperty(inAQ, inID, &running, &dataSize);
        running ? [player _audioQueueDidStart] : [player _audioQueueDidStop];
    }
}
