//
//  ViewController.m
//  AudioEngineAndOpenEarsDemo
//
//  Created by Ryan McLeod on 6/29/15.
//  Copyright (c) 2015 Ryan McLeod. All rights reserved.
//

#import "ViewController.h"


#define kOutputBus 0
#define kInputBus 1

typedef NS_ENUM(NSUInteger, segmentControl) {
    openEarsSegment = 0,
    taaeSegment = 1
};


@interface ViewController ()

@property (retain, nonatomic) IBOutlet UISwitch *openEarsSwitch;
@property (retain, nonatomic) IBOutlet UISwitch *audioEngineSwitch;
@property (retain, nonatomic) IBOutlet UILabel *debugLabel;

// AudioEngine
@property (strong, nonatomic) AEAudioController *aeAudioController;
@property (strong, nonatomic) dispatch_queue_t audioProcessingQueue;
// Float converter vars
@property (strong, nonatomic) AEFloatConverter *floatConverter;
@property float **floatBuffers;
@property AudioStreamBasicDescription streamFormat;

// OpenEars
@property (strong, nonatomic) NSString *languageModelPath;
@property (strong, nonatomic) NSString *dictionaryPath;
@property (strong, nonatomic) OEEventsObserver *openEarsEventsObserver;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.openEarsSwitch addTarget:self action:@selector(switchOpenEars) forControlEvents:UIControlEventValueChanged];
    [self.audioEngineSwitch addTarget:self action:@selector(switchAudioEngine) forControlEvents:UIControlEventValueChanged];
    
    // Initialize parts of both libraries that we expect to be persistent and reusable
    [self initOpenEarsComponents];
    [self initAudioEngineComponents];
    [self.debugLabel setText:@"OpenEars/TAAE initialized"];
}

#pragma mark - UI

- (void) switchOpenEars {
    if (self.openEarsSwitch.on) {
        [self.audioEngineSwitch setEnabled:NO];
        [self startOpenEars];
    } else {
        [self stopOpenEars];
        [self.audioEngineSwitch setEnabled:YES];
    }
}

- (void) switchAudioEngine {
    if (self.audioEngineSwitch.on) {
        [self.openEarsSwitch setEnabled:NO];
        [self startAudioEngine];
    } else {
        [self stopAudioEngine];
        [self.openEarsSwitch setEnabled:YES];
    }
}

#pragma mark - AudioEngine Helpers

// Should only be run once
- (void) initAudioEngineComponents {
    if (self.aeAudioController) {
        [self.aeAudioController stop];
        
        // Remove receivers if they exist
        for (id<AEAudioReceiver> receiver in [self.aeAudioController inputReceivers]) {
            [self.aeAudioController removeInputReceiver:receiver];
        }
    }
    
    self.aeAudioController = [[AEAudioController alloc] initWithAudioDescription:[AEAudioController nonInterleaved16BitStereoAudioDescription] inputEnabled:YES];
    
    self.audioProcessingQueue = dispatch_queue_create("self.edu.microphoneSamplingQueue", NULL);
    
    // Prep Float converter (depends on AE existing)
    self.streamFormat = [AEAudioController nonInterleaved16BitStereoAudioDescription];
    
    UInt32 bufferFrameCount;
    UInt32 propSize = sizeof(bufferFrameCount);
    AudioUnitGetProperty(self.aeAudioController.audioUnit,
                         kAudioUnitProperty_MaximumFramesPerSlice,
                         kAudioUnitScope_Global,
                         kOutputBus,
                         &bufferFrameCount,
                         &propSize);
    
    UInt32 bufferFrameSize = self.streamFormat.mBytesPerFrame;
    self.floatConverter = [[AEFloatConverter alloc] initWithSourceFormat:self.streamFormat];
    
    free(self.floatBuffers);
    self.floatBuffers = (float**)malloc(sizeof(float*)*self.streamFormat.mChannelsPerFrame);
    for ( int i=0; i<self.streamFormat.mChannelsPerFrame; i++ ) {
        self.floatBuffers[i] = (float*)calloc(bufferFrameCount, bufferFrameSize);
        assert(self.floatBuffers[i]);
    }
    
    NSLog(@"Debug: Initialized TAAE");
}

// Start should only be run after initalizing or stopping
- (void) startAudioEngine {
    static UInt32 frameNum = 0;
    
    [self.debugLabel setText:@"TAAE starting"];

    // we run update in case OpenEars changed something TAAE didn't expect to change under its feet
//    [self.aeAudioController updateWithAudioDescription:[AEAudioController nonInterleaved16BitStereoAudioDescription] inputEnabled:YES useVoiceProcessing:NO outputEnabled:NO];
    
    NSAssert(self.aeAudioController, @"Could not start/update AEAudioController");
    
    AEBlockAudioReceiver *blockAudioReceiver = [AEBlockAudioReceiver audioReceiverWithBlock:^(void *source, const AudioTimeStamp *time, UInt32 frames, AudioBufferList *audio) {
        
        // setup AEFC with stream type and buffers
        AEFloatConverterToFloat(self.floatConverter,
                                audio,
                                self.floatBuffers,
                                frames);
        
        // Normal frame processing usually happens here
        // Instead we'll just log a number so we know something is happening
        NSLog(@"audio frame #%d received", frameNum++);
    }];
    
    // Add our block processor to the mic input channel
    [self.aeAudioController addInputReceiver:blockAudioReceiver forChannels:@[@0]];
    
    // Attempt to start TAAE
    NSError *error = NULL;
    BOOL result = [self.aeAudioController start:&error];
    
    if ( !result ) {
        // Report error
        NSLog(@"Audio Engine initialization error: %@", error);
    }

    [self.debugLabel setText:@"TAAE started"];
}

- (void) stopAudioEngine {
    [self.debugLabel setText:@"TAAE stopping"];
    
    if (self.aeAudioController) {
        // Stop the engine
        [self.aeAudioController stop];
        
        // Remove receivers if they exist
        for (id<AEAudioReceiver> receiver in [self.aeAudioController inputReceivers]) {
            [self.aeAudioController removeInputReceiver:receiver];
        }
    }
    
    [self.debugLabel setText:@"TAAE stopped"];
}

#pragma mark - OpenEars Helpers

- (void) initOpenEarsComponents {
    OELanguageModelGenerator *lmGenerator = [[OELanguageModelGenerator alloc] init];
    
    // Init our dummy languageModel
    NSArray  *words = [NSArray arrayWithObjects:@"TEST", @"TESTING", nil];
    NSString *name  = @"TestLanguageModelFiles";
    NSError  *err   = [lmGenerator generateLanguageModelFromArray:words withFilesNamed:name forAcousticModelAtPath:[OEAcousticModel pathToModel:@"AcousticModelEnglish"]];
    
    if(err == nil) {
        self.languageModelPath  = [lmGenerator pathToSuccessfullyGeneratedLanguageModelWithRequestedName:name];
        self.dictionaryPath     = [lmGenerator pathToSuccessfullyGeneratedDictionaryWithRequestedName:name];
    } else {
        NSLog(@"Error: %@", [err localizedDescription]);
    }
    
    // Set-up our observer for testing purposes
    self.openEarsEventsObserver = [[OEEventsObserver alloc] init];
    [self.openEarsEventsObserver setDelegate:self];

    NSLog(@"Debug: Initialized OpenEars");
}


- (void) startOpenEars {
    [self.debugLabel setText:@"OpenEars starting"];
    
    [[OEPocketsphinxController sharedInstance] setVerbosePocketSphinx:YES];
    
    [[OEPocketsphinxController sharedInstance] setActive:TRUE error:nil];
    [[OEPocketsphinxController sharedInstance] startListeningWithLanguageModelAtPath:self.languageModelPath dictionaryAtPath:self.dictionaryPath acousticModelAtPath:[OEAcousticModel pathToModel:@"AcousticModelEnglish"] languageModelIsJSGF:NO];
    
    [self.debugLabel setText:@"OpenEars started"];
}

- (void) stopOpenEars {
    [self.debugLabel setText:@"OpenEars stopping"];

    [[OEPocketsphinxController sharedInstance] stopListening];
    [[OEPocketsphinxController sharedInstance] setActive:NO error:nil];
    
    [self.debugLabel setText:@"OpenEars stopped"];
}



#pragma mark - Helpers

// Useful for introducing an artifical pause after shutting down an engine
- (void) waitFor:(NSTimeInterval)time {
    [self.debugLabel setText:[NSString stringWithFormat:@"Waiting for %.1fs", time]];
    [NSThread sleepForTimeInterval:time];
    [self.debugLabel setText:@"Wait over"];
}




#pragma mark - OEEventsObserverDelegate

- (void) pocketsphinxDidReceiveHypothesis:(NSString *)hypothesis recognitionScore:(NSString *)recognitionScore utteranceID:(NSString *)utteranceID {
    NSLog(@"The received hypothesis is %@ with a score of %@ and an ID of %@", hypothesis, recognitionScore, utteranceID);
}

- (void) pocketsphinxDidStartListening {
    NSLog(@"Pocketsphinx is now listening.");
}

- (void) pocketsphinxDidDetectSpeech {
    NSLog(@"Pocketsphinx has detected speech.");
}

- (void) pocketsphinxDidDetectFinishedSpeech {
    NSLog(@"Pocketsphinx has detected a period of silence, concluding an utterance.");
}

- (void) pocketsphinxDidStopListening {
    NSLog(@"Pocketsphinx has stopped listening.");
}

- (void) pocketsphinxDidSuspendRecognition {
    NSLog(@"Pocketsphinx has suspended recognition.");
}

- (void) pocketsphinxDidResumeRecognition {
    NSLog(@"Pocketsphinx has resumed recognition.");
}

- (void) pocketsphinxDidChangeLanguageModelToFile:(NSString *)newLanguageModelPathAsString andDictionary:(NSString *)newDictionaryPathAsString {
    NSLog(@"Pocketsphinx is now using the following language model: \n%@ and the following dictionary: %@",newLanguageModelPathAsString,newDictionaryPathAsString);
}

- (void) pocketSphinxContinuousSetupDidFailWithReason:(NSString *)reasonForFailure {
    NSLog(@"Listening setup wasn't successful and returned the failure reason: %@", reasonForFailure);
}

- (void) pocketSphinxContinuousTeardownDidFailWithReason:(NSString *)reasonForFailure {
    NSLog(@"Listening teardown wasn't successful and returned the failure reason: %@", reasonForFailure);
}

- (void) testRecognitionCompleted {
    NSLog(@"A test file that was submitted for recognition is now complete.");
}


@end
