#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

#include <CoreFoundation/CoreFoundation.h>

typedef struct { float x; float y; } MTPoint;
typedef struct { MTPoint position; MTPoint velocity; } MTReadout;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int fingerID;
    int handID;
    MTReadout normalized;
    float size;
    int pressure;
    float angle;
    float majorAxis;
    float minorAxis;
    MTReadout absolute;
    int unknown1;
    int unknown2;
    float zDensity;
} MTTouch;

typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(MTDeviceRef device,
                                         MTTouch *touches,
                                         int numTouches,
                                         double timestamp,
                                         int frame);


#endif
