#ifndef BridgeHeader_h
#define BridgeHeader_h

#import "WireGuardKitC.h"
#include <mach/mach_init.h>

// Swift 6 rejects direct use of the mach_task_self_ global.
static inline mach_port_t tunnel_task_self(void) { return mach_task_self(); }

#endif /* BridgeHeader_h */
