//
//  ViewController.m
//  FFT
//
//  Created by Syed Haris Ali on 12/1/13.
//  Updated by Syed Haris Ali on 1/23/16.
//  Copyright (c) 2013 Syed Haris Ali. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

// This program is for song-level multi-F0 matching algorithm

#import "ViewController.h"

static vDSP_Length const fftSize = 8192;
NSDate *startTime, *currentTime;
NSTimeInterval interval;
int lastBeat;

typedef struct chord {
    int numOfNotes;
    int *notes;
} Chord;

typedef struct song {
    char *songName;
    int numofChords;
    Chord *chords;
    float tempo;
    float division;
} Song;

Song mySong;
BOOL isFinished = false;

static const float freqBase[88] = {
    // Note A0 - B0
    27.5, 29.135235, 30.867706,
    // Note C1 - B1
    32.703195, 34.647828, 36.708095, 38.890872, 41.203444, 43.653528,
    46.249302, 48.999429, 51.913087, 55, 58.27047, 61.735412,
    // Note C2 - B2
    65.406391, 69.295657, 73.416191, 77.781745, 82.406889, 87.307057,
    92.498605, 97.998858, 103.82617, 110, 116.54094, 123.47082,
    // Note C3 - B3
    130.812782, 138.591315, 146.832383, 155.563491, 164.813778, 174.614115,
    184.997211, 195.997717, 207.652348, 220.000000, 233.081880, 246.941650,
    // Note C4 - B4
    261.625565, 277.182630, 293.664767, 311.126983, 329.627556, 349.228231,
    369.994422, 391.995435, 415.304697, 440.000000, 466.163761, 493.883301,
    // Note C5 - B5
    523.251130, 554.365261, 587.329535, 622.253967, 659.255113, 698.456462,
    739.988845, 783.990871, 830.609395, 880.000000, 932.327523, 987.766602,
    // Note C6 - B6
    1046.502261, 1108.730523, 1174.659071, 1244.507934, 1318.510227, 1396.912925,
    1479.97769, 1567.981743, 1661.21879, 1760, 1864.655046, 1975.533205,
    // Note C7 - B7
    2093.004522, 2217.461047, 2349.318143, 2489.015869, 2637.020455, 2793.825851,
    2959.955381, 3135.963487, 3322.43758, 3520, 3729.310092, 3951.06641,
    // Note C8
    4186.009044
};

static const char *notes[] = {
    "A0", "A#0", "B0",
    "C1", "C#1", "D1", "D#1", "E1", "F1", "F#1", "G1", "G#1", "A1", "A#1", "B1",
    "C2", "C#2", "D2", "D#2", "E2", "F2", "F#2", "G2", "G#2", "A2", "A#2", "B2",
    "C3", "C#3", "D3", "D#3", "E3", "F3", "F#3", "G3", "G#3", "A3", "A#3", "B3",
    "C4", "C#4", "D4", "D#4", "E4", "F4", "F#4", "G4", "G#4", "A4", "A#4", "B4",
    "C5", "C#5", "D5", "D#5", "E5", "F5", "F#5", "G5", "G#5", "A5", "A#5", "B5",
    "C6", "C#6", "D6", "D#6", "E6", "F6", "F#6", "G6", "G#6", "A6", "A#6", "B6",
    "C7", "C#7", "D7", "D#7", "E7", "F7", "F#7", "G7", "G#7", "A7", "A#7", "B7",
    "C8",
    "X"
};

@implementation ViewController

//------------------------------------------------------------------------------
#pragma mark - Status Bar Style
//------------------------------------------------------------------------------

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

//------------------------------------------------------------------------------
#pragma mark - View Lifecycle
//------------------------------------------------------------------------------

- (void)viewDidLoad
{
    [super viewDidLoad];

    //
    // Setup the AVAudioSession. EZMicrophone will not work properly on iOS
    // if you don't do this!
    //
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error;
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    if (error)
    {
        NSLog(@"Error setting up audio session category: %@", error.localizedDescription);
    }
    [session setActive:YES error:&error];
    if (error)
    {
        NSLog(@"Error setting up audio session active: %@", error.localizedDescription);
    }
    
    //
    // Load Song Information
    //
    [self loadSongInformation:1];
    // print out song chords
    printf("-------------------------\n");
    printf("|\tsongName\t%s\n", mySong.songName);
    printf("|\ttempo\t\t%3f\n", mySong.tempo);
    printf("|\tdivision\t%3f\n", mySong.division);
    for (int i = 0; i < mySong.numofChords; i++) {
        printf("|\t\t- Chord %d: ", i);
        for (int j = 0; j < mySong.chords[i].numOfNotes; j++) {
            printf("%s ", notes[mySong.chords[i].notes[j]]);
        }
        printf("\n");
    }
    printf("-------------------------\n");
    isFinished = false;

    //
    // Setup time domain audio plot
    //
    self.audioPlotTime.plotType = EZPlotTypeBuffer;
    self.maxFrequencyLabel.numberOfLines = 0;

    //
    // Setup frequency domain audio plot
    //
    self.audioPlotFreq.shouldFill = YES;
    self.audioPlotFreq.plotType = EZPlotTypeBuffer;
    self.audioPlotFreq.shouldCenterYAxis = NO;

    //
    // Create an instance of the microphone and tell it to use this view controller instance as the delegate
    //
    self.microphone = [EZMicrophone microphoneWithDelegate:self withAudioStreamBasicDescription:[self customAudioStreamBasicDescriptionWithSampleRate:44100.f]];

    //
    // Create an instance of the EZAudioFFTRolling to keep a history of the incoming audio data and calculate the FFT.
    //
    self.fft = [EZAudioFFTRolling fftWithWindowSize:fftSize
                                         sampleRate:self.microphone.audioStreamBasicDescription.mSampleRate
                                           delegate:self];

    //
    // Start the mic
    //
    [self.microphone startFetchingAudio];
    
    //
    // Start the timing process
    //
    startTime = [NSDate date];
    lastBeat = 0;
    printf("Get Ready 1 2 3 4 and PLAY!\n");
}

//------------------------------------------------------------------------------
#pragma mark - EZMicrophoneDelegate
//------------------------------------------------------------------------------

-(void)    microphone:(EZMicrophone *)microphone
     hasAudioReceived:(float **)buffer
       withBufferSize:(UInt32)bufferSize
 withNumberOfChannels:(UInt32)numberOfChannels
{
    float tempo = mySong.tempo, division = mySong.division;
    float beatInterval = 60 / tempo / division;
    
    currentTime = [NSDate date];
    interval = [currentTime timeIntervalSinceDate:startTime];
    if (floor(interval / beatInterval) > lastBeat) {
        lastBeat = floor(interval / beatInterval);
        if (lastBeat <= 4) {
            printf("\t%d\n", lastBeat);
        } else if (lastBeat <= mySong.numofChords+4) {
            printf("Play: ");
            for (int i = 0; i < mySong.chords[lastBeat-5].numOfNotes; i++) {
                printf("%s ", notes[mySong.chords[lastBeat-5].notes[i]]);
            }
            printf("\n");
        } else {
            if (!isFinished) {
                printf("Song finished :)\n");
                isFinished = true;
            }
        }
    }
    
    //
    // Calculate the FFT, will trigger EZAudioFFTDelegate
    //
    [self.fft computeFFTWithBuffer:buffer[0] withBufferSize:bufferSize];

    __weak typeof (self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf.audioPlotTime updateBuffer:buffer[0]
                              withBufferSize:bufferSize];
    });
}

//------------------------------------------------------------------------------
#pragma mark - EZAudioFFTDelegate
//------------------------------------------------------------------------------

- (void)        fft:(EZAudioFFT *)fft
 updatedWithFFTData:(float *)fftData
         bufferSize:(vDSP_Length)bufferSize
{
    float maxFrequency = [fft maxFrequency];
    NSString *noteName = [EZAudioUtilities noteNameStringForFrequency:maxFrequency
                                                        includeOctave:YES];

    __weak typeof (self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        weakSelf.maxFrequencyLabel.text = [NSString stringWithFormat:@"Highest Note: %@,\nFrequency: %.2f", noteName, maxFrequency];
        [weakSelf.audioPlotFreq updateBuffer:fftData withBufferSize:(UInt32)bufferSize/8];
    });
}

/**
 音频捕获参数设置
 
 @return return value description
 */
- (AudioStreamBasicDescription)customAudioStreamBasicDescriptionWithSampleRate:(CGFloat)sampleRate
{
    AudioStreamBasicDescription asbd;
    UInt32 floatByteSize   = sizeof(float);
    // 每个通道中的位数，1byte = 8bit
    asbd.mBitsPerChannel   = 8 * floatByteSize;
    // 每一帧中的字节数
    asbd.mBytesPerFrame    = floatByteSize;
    // 一个数据包中的字节数
    asbd.mBytesPerPacket   = floatByteSize;
    // 每一帧数据中的通道数，单声道为1，立体声为2
    asbd.mChannelsPerFrame = 1;
    // 每种格式特定的标志，无损编码 ，0表示没有
    asbd.mFormatFlags      = kAudioFormatFlagIsFloat|kAudioFormatFlagIsNonInterleaved;
    // 采样数据的类型，PCM,AAC等
    asbd.mFormatID         = kAudioFormatLinearPCM;
    // 一个数据包中的帧数，每个packet的帧数。如果是未压缩的音频数据，值是1。动态帧率格式，这个值是一个较大的固定数字，比如说AAC的1024。如果是动态大小帧数（比如Ogg格式）设置为0。
    asbd.mFramesPerPacket  = 1;
    // 设置采样率：Hz
    // 采样率：Hz
    asbd.mSampleRate       = sampleRate;
    return asbd;
}

#pragma mark - Load Song Information
- (void) loadSongInformation:(int)songIndex
{
    Chord *temp_chord = mySong.chords;
    int *temp_note = NULL;
    
    switch (songIndex) {
        case 0: // default test song
            // Set song basics
            mySong.songName = "GL_test_song";    // Do Re Mi
            mySong.tempo = 60.0;
            mySong.division = 1.0;
            // Starting writing chords
            mySong.numofChords = 4;
            mySong.chords = (Chord *) malloc(sizeof(Chord) * mySong.numofChords);
            if (mySong.chords) {
                printf("(%s) Loading started...\n", mySong.songName);
            } else {
                printf("(%s) Loading failed. Out of memory.\n", mySong.songName);
            }
            // Fill up each chord with song notes
            temp_chord = mySong.chords;
            temp_note = NULL;
            // Chord 0  C4
            temp_chord[0].numOfNotes = 1;
            temp_chord[0].notes = (int *) malloc(sizeof(int) * temp_chord[0].numOfNotes);
            if (temp_chord[0].notes) {
                temp_note = temp_chord[0].notes;
                temp_note[0] = 39;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 1  C5
            temp_chord[1].numOfNotes = 1;
            temp_chord[1].notes = (int *) malloc(sizeof(int) * temp_chord[1].numOfNotes);
            if (temp_chord[1].notes) {
                temp_note = temp_chord[1].notes;
                temp_note[0] = 51;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 2  C4 C5
            temp_chord[2].numOfNotes = 2;
            temp_chord[2].notes = (int *) malloc(sizeof(int) * temp_chord[2].numOfNotes);
            if (temp_chord[2].notes) {
                temp_note = temp_chord[2].notes;
                temp_note[0] = 39;
                temp_note[1] = 51;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 3  C3 C4 C5
            temp_chord[3].numOfNotes = 3;
            temp_chord[3].notes = (int *) malloc(sizeof(int) * temp_chord[3].numOfNotes);
            if (temp_chord[0].notes) {
                temp_note = temp_chord[3].notes;
                temp_note[0] = 27;
                temp_note[1] = 39;
                temp_note[2] = 51;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            printf("(%s) Loading completed!\n", mySong.songName);
            break;
            
        case 1: // little_star_1
            // Set song basics
            mySong.songName = "little_star_1";
            mySong.tempo = 60.0;
            mySong.division = 1.0;
            // Starting writing chords
            mySong.numofChords = 48;
            mySong.chords = (Chord *) malloc(sizeof(Chord) * mySong.numofChords);
            if (mySong.chords) {
                printf("(%s) Loading started...\n", mySong.songName);
            } else {
                printf("(%s) Loading failed. Out of memory.\n", mySong.songName);
            }
            // Starting writing chords
            temp_chord = mySong.chords;
            temp_note = NULL;
            // Measure 1
            // Chord 0      C4
            temp_chord[0].numOfNotes = 1;
            temp_chord[0].notes = (int *) malloc(sizeof(int) * temp_chord[0].numOfNotes);
            if (temp_chord[0].notes) {
                temp_note = temp_chord[0].notes;
                temp_note[0] = 39;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 1      C4
            temp_chord[1].numOfNotes = 1;
            temp_chord[1].notes = (int *) malloc(sizeof(int) * temp_chord[1].numOfNotes);
            if (temp_chord[1].notes) {
                temp_note = temp_chord[1].notes;
                temp_note[0] = 39;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 2      G4
            temp_chord[2].numOfNotes = 1;
            temp_chord[2].notes = (int *) malloc(sizeof(int) * temp_chord[2].numOfNotes);
            if (temp_chord[2].notes) {
                temp_note = temp_chord[2].notes;
                temp_note[0] = 46;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 3      G4
            temp_chord[3].numOfNotes = 1;
            temp_chord[3].notes = (int *) malloc(sizeof(int) * temp_chord[3].numOfNotes);
            if (temp_chord[3].notes) {
                temp_note = temp_chord[3].notes;
                temp_note[0] = 46;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Measure 2
            // Chord 4      A4
            temp_chord[4].numOfNotes = 1;
            temp_chord[4].notes = (int *) malloc(sizeof(int) * temp_chord[4].numOfNotes);
            if (temp_chord[4].notes) {
                temp_note = temp_chord[4].notes;
                temp_note[0] = 48;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 5      A4
            temp_chord[5].numOfNotes = 1;
            temp_chord[5].notes = (int *) malloc(sizeof(int) * temp_chord[5].numOfNotes);
            if (temp_chord[5].notes) {
                temp_note = temp_chord[5].notes;
                temp_note[0] = 48;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 6      G4
            temp_chord[6].numOfNotes = 1;
            temp_chord[6].notes = (int *) malloc(sizeof(int) * temp_chord[6].numOfNotes);
            if (temp_chord[6].notes) {
                temp_note = temp_chord[6].notes;
                temp_note[0] = 46;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 7      X
            temp_chord[7].numOfNotes = 1;
            temp_chord[7].notes = (int *) malloc(sizeof(int) * temp_chord[7].numOfNotes);
            if (temp_chord[7].notes) {
                temp_note = temp_chord[7].notes;
                temp_note[0] = 88;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Measure 3
            // Chord 8      F4
            temp_chord[8].numOfNotes = 1;
            temp_chord[8].notes = (int *) malloc(sizeof(int) * temp_chord[8].numOfNotes);
            if (temp_chord[8].notes) {
                temp_note = temp_chord[8].notes;
                temp_note[0] = 44;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 9      F4
            temp_chord[9].numOfNotes = 1;
            temp_chord[9].notes = (int *) malloc(sizeof(int) * temp_chord[9].numOfNotes);
            if (temp_chord[9].notes) {
                temp_note = temp_chord[9].notes;
                temp_note[0] = 44;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 10     E4
            temp_chord[10].numOfNotes = 1;
            temp_chord[10].notes = (int *) malloc(sizeof(int) * temp_chord[10].numOfNotes);
            if (temp_chord[10].notes) {
                temp_note = temp_chord[10].notes;
                temp_note[0] = 43;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 11     E4
            temp_chord[11].numOfNotes = 1;
            temp_chord[11].notes = (int *) malloc(sizeof(int) * temp_chord[11].numOfNotes);
            if (temp_chord[11].notes) {
                temp_note = temp_chord[11].notes;
                temp_note[0] = 43;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Measure 4
            // Chord 12     D4
            temp_chord[12].numOfNotes = 1;
            temp_chord[12].notes = (int *) malloc(sizeof(int) * temp_chord[12].numOfNotes);
            if (temp_chord[12].notes) {
                temp_note = temp_chord[12].notes;
                temp_note[0] = 41;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 13     D4
            temp_chord[13].numOfNotes = 1;
            temp_chord[13].notes = (int *) malloc(sizeof(int) * temp_chord[13].numOfNotes);
            if (temp_chord[13].notes) {
                temp_note = temp_chord[13].notes;
                temp_note[0] = 41;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 14     C4
            temp_chord[14].numOfNotes = 1;
            temp_chord[14].notes = (int *) malloc(sizeof(int) * temp_chord[14].numOfNotes);
            if (temp_chord[14].notes) {
                temp_note = temp_chord[14].notes;
                temp_note[0] = 39;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 15     X
            temp_chord[15].numOfNotes = 1;
            temp_chord[15].notes = (int *) malloc(sizeof(int) * temp_chord[15].numOfNotes);
            if (temp_chord[15].notes) {
                temp_note = temp_chord[15].notes;
                temp_note[0] = 88;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Measure 5
            // Chord 16     G4
            temp_chord[16].numOfNotes = 1;
            temp_chord[16].notes = (int *) malloc(sizeof(int) * temp_chord[16].numOfNotes);
            if (temp_chord[16].notes) {
                temp_note = temp_chord[16].notes;
                temp_note[0] = 46;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 17     G4
            temp_chord[17].numOfNotes = 1;
            temp_chord[17].notes = (int *) malloc(sizeof(int) * temp_chord[17].numOfNotes);
            if (temp_chord[17].notes) {
                temp_note = temp_chord[17].notes;
                temp_note[0] = 46;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 18     F4
            temp_chord[18].numOfNotes = 1;
            temp_chord[18].notes = (int *) malloc(sizeof(int) * temp_chord[18].numOfNotes);
            if (temp_chord[18].notes) {
                temp_note = temp_chord[18].notes;
                temp_note[0] = 44;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 19     F4
            temp_chord[19].numOfNotes = 1;
            temp_chord[19].notes = (int *) malloc(sizeof(int) * temp_chord[19].numOfNotes);
            if (temp_chord[19].notes) {
                temp_note = temp_chord[19].notes;
                temp_note[0] = 44;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Measure 6
            // Chord 20     E4
            temp_chord[20].numOfNotes = 1;
            temp_chord[20].notes = (int *) malloc(sizeof(int) * temp_chord[20].numOfNotes);
            if (temp_chord[20].notes) {
                temp_note = temp_chord[20].notes;
                temp_note[0] = 43;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 21     E4
            temp_chord[21].numOfNotes = 1;
            temp_chord[21].notes = (int *) malloc(sizeof(int) * temp_chord[21].numOfNotes);
            if (temp_chord[21].notes) {
                temp_note = temp_chord[21].notes;
                temp_note[0] = 43;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 22     D4
            temp_chord[22].numOfNotes = 1;
            temp_chord[22].notes = (int *) malloc(sizeof(int) * temp_chord[22].numOfNotes);
            if (temp_chord[22].notes) {
                temp_note = temp_chord[22].notes;
                temp_note[0] = 41;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 23     X
            temp_chord[23].numOfNotes = 1;
            temp_chord[23].notes = (int *) malloc(sizeof(int) * temp_chord[23].numOfNotes);
            if (temp_chord[23].notes) {
                temp_note = temp_chord[23].notes;
                temp_note[0] = 88;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Measure 7
            // Chord 24     G4
            temp_chord[24].numOfNotes = 1;
            temp_chord[24].notes = (int *) malloc(sizeof(int) * temp_chord[24].numOfNotes);
            if (temp_chord[24].notes) {
                temp_note = temp_chord[24].notes;
                temp_note[0] = 46;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 25     G4
            temp_chord[25].numOfNotes = 1;
            temp_chord[25].notes = (int *) malloc(sizeof(int) * temp_chord[25].numOfNotes);
            if (temp_chord[25].notes) {
                temp_note = temp_chord[25].notes;
                temp_note[0] = 46;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 26     F4
            temp_chord[26].numOfNotes = 1;
            temp_chord[26].notes = (int *) malloc(sizeof(int) * temp_chord[26].numOfNotes);
            if (temp_chord[26].notes) {
                temp_note = temp_chord[26].notes;
                temp_note[0] = 44;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 27     F4
            temp_chord[27].numOfNotes = 1;
            temp_chord[27].notes = (int *) malloc(sizeof(int) * temp_chord[27].numOfNotes);
            if (temp_chord[27].notes) {
                temp_note = temp_chord[27].notes;
                temp_note[0] = 44;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Measure 8
            // Chord 28     E4
            temp_chord[28].numOfNotes = 1;
            temp_chord[28].notes = (int *) malloc(sizeof(int) * temp_chord[28].numOfNotes);
            if (temp_chord[28].notes) {
                temp_note = temp_chord[28].notes;
                temp_note[0] = 43;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 29     E4
            temp_chord[29].numOfNotes = 1;
            temp_chord[29].notes = (int *) malloc(sizeof(int) * temp_chord[29].numOfNotes);
            if (temp_chord[29].notes) {
                temp_note = temp_chord[29].notes;
                temp_note[0] = 43;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 30     D4
            temp_chord[30].numOfNotes = 1;
            temp_chord[30].notes = (int *) malloc(sizeof(int) * temp_chord[30].numOfNotes);
            if (temp_chord[30].notes) {
                temp_note = temp_chord[30].notes;
                temp_note[0] = 41;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 31     X
            temp_chord[31].numOfNotes = 1;
            temp_chord[31].notes = (int *) malloc(sizeof(int) * temp_chord[31].numOfNotes);
            if (temp_chord[31].notes) {
                temp_note = temp_chord[31].notes;
                temp_note[0] = 88;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Measure 9
            // Chord 32     C4
            temp_chord[32].numOfNotes = 1;
            temp_chord[32].notes = (int *) malloc(sizeof(int) * temp_chord[32].numOfNotes);
            if (temp_chord[32].notes) {
                temp_note = temp_chord[32].notes;
                temp_note[0] = 39;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 33     C4
            temp_chord[33].numOfNotes = 1;
            temp_chord[33].notes = (int *) malloc(sizeof(int) * temp_chord[33].numOfNotes);
            if (temp_chord[33].notes) {
                temp_note = temp_chord[33].notes;
                temp_note[0] = 39;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 34     G4
            temp_chord[34].numOfNotes = 1;
            temp_chord[34].notes = (int *) malloc(sizeof(int) * temp_chord[34].numOfNotes);
            if (temp_chord[34].notes) {
                temp_note = temp_chord[34].notes;
                temp_note[0] = 46;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 35     G4
            temp_chord[35].numOfNotes = 1;
            temp_chord[35].notes = (int *) malloc(sizeof(int) * temp_chord[35].numOfNotes);
            if (temp_chord[35].notes) {
                temp_note = temp_chord[35].notes;
                temp_note[0] = 46;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Measure 10
            // Chord 36     A4
            temp_chord[36].numOfNotes = 1;
            temp_chord[36].notes = (int *) malloc(sizeof(int) * temp_chord[36].numOfNotes);
            if (temp_chord[36].notes) {
                temp_note = temp_chord[36].notes;
                temp_note[0] = 48;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 37     A4
            temp_chord[37].numOfNotes = 1;
            temp_chord[37].notes = (int *) malloc(sizeof(int) * temp_chord[37].numOfNotes);
            if (temp_chord[37].notes) {
                temp_note = temp_chord[37].notes;
                temp_note[0] = 48;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 38     G4
            temp_chord[38].numOfNotes = 1;
            temp_chord[38].notes = (int *) malloc(sizeof(int) * temp_chord[38].numOfNotes);
            if (temp_chord[38].notes) {
                temp_note = temp_chord[38].notes;
                temp_note[0] = 46;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 39     X
            temp_chord[39].numOfNotes = 1;
            temp_chord[39].notes = (int *) malloc(sizeof(int) * temp_chord[39].numOfNotes);
            if (temp_chord[39].notes) {
                temp_note = temp_chord[39].notes;
                temp_note[0] = 88;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Measure 11
            // Chord 40     F4
            temp_chord[40].numOfNotes = 1;
            temp_chord[40].notes = (int *) malloc(sizeof(int) * temp_chord[40].numOfNotes);
            if (temp_chord[40].notes) {
                temp_note = temp_chord[40].notes;
                temp_note[0] = 44;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 41     F4
            temp_chord[41].numOfNotes = 1;
            temp_chord[41].notes = (int *) malloc(sizeof(int) * temp_chord[41].numOfNotes);
            if (temp_chord[41].notes) {
                temp_note = temp_chord[41].notes;
                temp_note[0] = 44;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 42     E4
            temp_chord[42].numOfNotes = 1;
            temp_chord[42].notes = (int *) malloc(sizeof(int) * temp_chord[42].numOfNotes);
            if (temp_chord[42].notes) {
                temp_note = temp_chord[42].notes;
                temp_note[0] = 43;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 43     E4
            temp_chord[43].numOfNotes = 1;
            temp_chord[43].notes = (int *) malloc(sizeof(int) * temp_chord[43].numOfNotes);
            if (temp_chord[43].notes) {
                temp_note = temp_chord[43].notes;
                temp_note[0] = 43;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Measure 12
            // Chord 44     D4
            temp_chord[44].numOfNotes = 1;
            temp_chord[44].notes = (int *) malloc(sizeof(int) * temp_chord[44].numOfNotes);
            if (temp_chord[44].notes) {
                temp_note = temp_chord[44].notes;
                temp_note[0] = 41;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 45     D4
            temp_chord[45].numOfNotes = 1;
            temp_chord[45].notes = (int *) malloc(sizeof(int) * temp_chord[45].numOfNotes);
            if (temp_chord[45].notes) {
                temp_note = temp_chord[45].notes;
                temp_note[0] = 41;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 46     C4
            temp_chord[46].numOfNotes = 1;
            temp_chord[46].notes = (int *) malloc(sizeof(int) * temp_chord[46].numOfNotes);
            if (temp_chord[46].notes) {
                temp_note = temp_chord[46].notes;
                temp_note[0] = 39;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            // Chord 47     X
            temp_chord[47].numOfNotes = 1;
            temp_chord[47].notes = (int *) malloc(sizeof(int) * temp_chord[47].numOfNotes);
            if (temp_chord[47].notes) {
                temp_note = temp_chord[47].notes;
                temp_note[0] = 88;
                temp_note = NULL;
            } else {
                printf("Out of memory!\n");
                exit(-1);
            }
            break;
            
        case 2: // little_star_2
            break;
            
        case 3: // little_star_3
            break;
            
            
    }
    return ;
}


@end
