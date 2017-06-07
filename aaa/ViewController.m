//
//  ViewController.m
//  aaa
//
//  Created by Seamus on 2017/6/5.
//  Copyright © 2017年 Seamus. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
@interface ViewController (){
    NSDictionary *videoSettings;
    CMTime frameTime;
}
@property (strong,nonatomic) AVAssetWriter *outputWriter;
@property (strong,nonatomic) AVAssetWriterInput *outputWriterInput;
@property (strong,nonatomic) AVAssetWriterInputPixelBufferAdaptor *bufferAdapter;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    UIImage *img = [UIImage imageNamed:@"IMG_0055.jpg"];
    [self makeVideoWithImages:@[img,img] seconds:2.5 block:^(NSString *videopath) {
        NSLog(@"video path:%@",videopath);
    }];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (NSString *)fileWithDicPath:(NSString *)_dictname fileName:(NSString *)_fname
{
    NSString *path = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"] stringByAppendingPathComponent:[_dictname copy]];
    BOOL bo = [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    
    if (!bo) {
        NSAssert(bo,@"创建目录失败");
    }
    
    NSString *result = [path stringByAppendingPathComponent:[NSString stringWithFormat:@"%@",_fname]];
    
    return result;
}

- (void)makeVideoWithImages:(NSArray *)images seconds:(CGFloat)seconds block:(void (^)(NSString *videopath)) block
{
    NSString *path = [self fileWithDicPath:@"pic" fileName:@"picmovie.mov"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    NSURL *url = [NSURL fileURLWithPath:path];
    NSError *error;
    
    UIImage *source = [images objectAtIndex:0];
    CGSize size = CGSizeMake(source.size.width*source.scale, source.size.height*source.scale);
    
    UIImageWriteToSavedPhotosAlbum(source, nil, nil, nil);
    
    videoSettings = @{AVVideoCodecKey : AVVideoCodecH264,
                      AVVideoWidthKey : [NSNumber numberWithInt:size.width],
                      AVVideoHeightKey : [NSNumber numberWithInt:size.height]};
    self.outputWriter = [[AVAssetWriter alloc] initWithURL:url
                                                  fileType:AVFileTypeQuickTimeMovie error:&error];
    
    self.outputWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                outputSettings:videoSettings];
    [self.outputWriter addInput:self.outputWriterInput];
    NSDictionary *bufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSNumber numberWithInt:kCVPixelFormatType_32RGBA], kCVPixelBufferPixelFormatTypeKey, nil];
    self.bufferAdapter = [[AVAssetWriterInputPixelBufferAdaptor alloc] initWithAssetWriterInput:self.outputWriterInput sourcePixelBufferAttributes:bufferAttributes];
    frameTime = CMTimeMake(seconds*600, 600);
    
    [self.outputWriter startWriting];
    [self.outputWriter startSessionAtSourceTime:kCMTimeZero];
    
    dispatch_queue_t mediaInputQueue = dispatch_queue_create("mediaInputQueue", NULL);
    
    __block NSInteger i = 0;
    
    NSInteger frameNumber = [images count];
    
    [self.outputWriterInput requestMediaDataWhenReadyOnQueue:mediaInputQueue usingBlock:^{
        while (YES){
            if (i >= frameNumber) {
                break;
            }
            if ([self.outputWriterInput isReadyForMoreMediaData]) {
                
                CVPixelBufferRef sampleBuffer;
                @autoreleasepool {
                    UIImage* img = [images objectAtIndex:i];
                    if (img == nil) {
                        i++;
//                        devLog(@"Warning: could not extract one of the frames");
                        continue;
                    }
                    sampleBuffer = [self newPixelBufferFromCGImage:[img CGImage]];
                }
                if (sampleBuffer) {
                    if (i == 0) {
                        [self.bufferAdapter appendPixelBuffer:sampleBuffer withPresentationTime:kCMTimeZero];
                    }else{
                        CMTime lastTime = CMTimeMake((i-1)*frameTime.timescale*seconds, frameTime.timescale);
                        CMTime presentTime = CMTimeAdd(lastTime, frameTime);
                        [self.bufferAdapter appendPixelBuffer:sampleBuffer withPresentationTime:presentTime];
                    }
                    CFRelease(sampleBuffer);
                    i++;
                }
            }
        }
        
        [self.outputWriterInput markAsFinished];
        [self.outputWriter finishWritingWithCompletionHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
//                NSError *error = nil;
//                [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
//                    [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:[NSURL fileURLWithPath:path]];
//                } error:&error];
                //
                block(path);
            });
        }];
        
        CVPixelBufferPoolRelease(self.bufferAdapter.pixelBufferPool);
    }];
    
}
- (CVPixelBufferRef)newPixelBufferFromCGImage:(CGImageRef)image
{
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
                             nil];
    
    CVPixelBufferRef pxbuffer = NULL;
    
    CGFloat frameWidth = [[videoSettings objectForKey:AVVideoWidthKey] floatValue];
    CGFloat frameHeight = [[videoSettings objectForKey:AVVideoHeightKey] floatValue];
    
    
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          frameWidth,
                                          frameHeight,
                                          kCVPixelFormatType_32ARGB,
                                          (__bridge CFDictionaryRef) options,
                                          &pxbuffer);
    
    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);
    
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    NSParameterAssert(pxdata != NULL);
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef context = CGBitmapContextCreate(pxdata,
                                                 frameWidth,
                                                 frameHeight,
                                                 8,
                                                 4 * frameWidth,
                                                 rgbColorSpace,
                                                 (CGBitmapInfo)kCGImageAlphaNoneSkipFirst);
    NSParameterAssert(context);
    CGContextConcatCTM(context, CGAffineTransformIdentity);
    CGContextDrawImage(context, CGRectMake(0,
                                           0,
                                           frameWidth,
                                           frameHeight),
                       image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    
    return pxbuffer;
}


@end
