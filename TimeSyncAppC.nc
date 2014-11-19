#include <Timer.h>
#include "TimeSync.h"


#define NEW_PRINTF_SEMANTICS
#include "printf.h"

configuration TimeSyncAppC {
}

implementation {

	//Componets used
	components MainC;
	components LedsC;
	components TimeSyncC as App;
	components new TimerMilliC() as Timer0;
	components new TimerMilliC() as Timer1;
	components ActiveMessageC;
	components new AMSenderC(AM_BLINKTORADIO);
	components new AMReceiverC(AM_BLINKTORADIO);
	components RandomC;
	components PrintfC;
	components SerialStartC;

	// channel switching
	components CC2420ActiveMessageC;
	components CC2420ControlC;

	//Wiring
	App.Boot -> MainC;
	App.Leds -> LedsC;
	App.LocalClock -> Timer0 ;
	App.LedTimer -> Timer1 ;
	App.Packet -> AMSenderC;
	App.AMPacket -> AMSenderC;
	App.AMControl -> ActiveMessageC;
	App.AMSend -> AMSenderC;
	App.Receive -> AMReceiverC;
	App.Random -> RandomC;


	App.CC2420Config -> CC2420ControlC;
	App -> CC2420ActiveMessageC.CC2420Packet; 

}
