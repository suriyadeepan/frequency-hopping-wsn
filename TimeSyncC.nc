#include <Timer.h>
#include "TimeSync.h"
#include "printf.h"
#include "CC2420.h"

module TimeSyncC 
{
	uses interface Boot;
	uses interface Leds;
	uses interface Timer<TMilli> as LocalClock;
	uses interface Timer<TMilli> as LedTimer;
	uses interface Packet;
	uses interface AMPacket;
	uses interface AMSend;
	uses interface Receive;
	uses interface SplitControl as AMControl;
	uses interface Random;

	// channel switching interfaces
	uses interface CC2420Packet;
	uses interface CC2420Config;

}

implementation 
{
	//message object to store received packet
	message_t pkt;

	// current channel
	uint16_t current;

	// previous data
	int32_t prev = -1;

	int32_t prop_delay;

	//Creates sync packet and sends sync request to the parent node.
 	void sendSyncReq ();

	//Calculates TPSN offset, RBS offset and timesync error.
  	void CalculateDelta(uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);

	//Last RBS pkt ID received by this node.
	uint32_t last_rbs_pkt_id = 0;

	//Local time of receiving with last_rbs_pkt_id.
	uint32_t last_rbs_recp_time = 0;

	//Last RBS pkt id received by root. This information is collected from parent.
	uint32_t root_rbs_pkt_id = 0;

	//Root local time of receiving root_rbs_pkt_id.
	uint32_t root_rbs_recp_time = 0;

	//Buffer to store old root rbs time.
	uint32_t last_rbs_buf[RBS_BUF_LEN];

	//pointer to the oldest entry in the buffer.
	uint32_t rbs_buf_pointer=0;

	//Time interval between TPSN sync request to parent and reply from parent.
	uint32_t time2sync=0;

	//Offset with root time according to RBS
	int32_t  offset_rbs ;

	//Offset with parent time according to TPSN
	int32_t offset_tpsn=0;

	//Offset with root time according to TPSN
	int32_t total_offset_tpsn = 0;

	// current time
	uint32_t tnow1 = 0;
// millisecond count
	uint16_t msec_count = 0;

	// temp
	uint32_t temp = 0;

	// prototypes
	void sendDataPkt();

	void setTransmitChannel();
	void setHostChannel();
	void setParentChannel();

	// count value ( updated every 1 s )
	uint16_t count = 0;

	//Event called after boot
	event void Boot.booted() 
	{
		uint8_t iterator;
		call AMControl.start();

		current = 11 + TOS_NODE_ID;

		// switch to host channel
		setHostChannel();


		//Initialize all values of the buf to zero.
		for(iterator=0;iterator<RBS_BUF_LEN;iterator++)
			last_rbs_buf[iterator] = 0;

	}

	//Event called after start done
	event void AMControl.startDone(error_t err) 
	{
		if (err == SUCCESS) {

			call LedTimer.startPeriodic(1);

			if (TOS_NODE_ID != 0)
			     call LocalClock.startPeriodic(pulse);
		}
		else {
			call AMControl.start();
		}
	}


	//Creates sync packet and sends sync request to the parent node.
	void sendSyncReq ()
	{
		SyncPacket* syncpkt = (SyncPacket*)(call Packet.getPayload(&pkt, sizeof(SyncPacket)));
		if (syncpkt == NULL) {
			printf ("NULL returned\n");
			printfflush();
			return;
		}

		//SyncPacket fields are populated. 
		syncpkt->T1 = call LocalClock.getNow();
		syncpkt->T2 = 0;
		syncpkt->T3 = 0;
		syncpkt-> ROOT_RBS_PKT_ID = 0;
		syncpkt-> ROOT_RBS_RECP_TIME = 0;
		syncpkt-> offset = 0;
		syncpkt-> type = 0;

		// switch to parent's channel
		setParentChannel();

		//Sends the SyncPacket to the parent as an unicast message.
		if (call AMSend.send((am_addr_t)topology_array[TOS_NODE_ID], 
		  &pkt, sizeof(SyncPacket)) == SUCCESS) {
			time2sync++;
		}

	}		


	void setTransmitChannel(){


		// switch to host channel
		call CC2420Config.setChannel(11 + TOS_NODE_ID + 1);
		call CC2420Config.sync();

	}

	void setHostChannel(){

		// switch to host channel
		call CC2420Config.setChannel(11 + TOS_NODE_ID);
		call CC2420Config.sync();

	}

	void setParentChannel(){

		// switch to host channel
		call CC2420Config.setChannel(11 + TOS_NODE_ID -1);
		call CC2420Config.sync();
	}


//Even called after send done
	event void AMSend.sendDone(message_t* msg, error_t err) 
	{

		call Leds.led0Toggle();
		setHostChannel();

	}

	//Event called after stop done
	event void AMControl.stopDone(error_t err) 
	{
	
	}

	// returns true if 'id' is one my child node.
	bool isMyChild ( am_addr_t id)
	{
		if ( topology_array[id] == TOS_NODE_ID && id != TOS_NODE_ID )
			return TRUE;
		return FALSE;
		
	}

	//returns true if 'id'  is my parent node.
	bool isMyParent ( am_addr_t id)
	{
		if (topology_array [TOS_NODE_ID] == id && id != TOS_NODE_ID)
			return TRUE;
		return FALSE;
	}

	//Generates a random number between 0 and 1.
	long double generate_random ()
	{
		uint32_t value = call Random.rand32();
        	long double probability = (long double)value / 4294967296;
		return probability;
	}
	
	//Event called when clock fires
	event void LocalClock.fired()
	{
		sendSyncReq();

		//call Leds.led2Toggle();
	}

  	//Event called when LedTimer fires
	event void LedTimer.fired()
	{
		if(TOS_NODE_ID != 0){// i'm a child
			temp = call LocalClock.getNow();
			temp = temp + offset_tpsn - prop_delay;
		}

		else
			temp = call LocalClock.getNow();

		// every 100 ms send a packet to child
		if(temp % 100 == 0){

			// set channel for transmission
			setTransmitChannel();
			sendDataPkt();

		}

		// change transmission, receive channel every 1000 ms = 1 s
		if(temp % 2000 == 0){
			
			// update channel
			current = current + 1;
			
			if(current > 25)
				current = TOS_NODE_ID + 11;
			
			printfflush();
			printf("ID : %u, listening @ %u\n",TOS_NODE_ID,current);
			printfflush();

		}

		

	}

	void sendDataPkt(){

		//Creates a data packet to send to the child 
		DataPacket* dpkt = (DataPacket*)(call Packet.getPayload(&pkt, sizeof(SyncPacket)));
		dpkt-> dat = count;
		dpkt-> type = 1;

		// Sends the packet to the child.
		if (call AMSend.send((am_addr_t)(TOS_NODE_ID+1), 
		  &pkt, sizeof(DataPacket)) == SUCCESS) {
			//printf("success\n");
			//printfflush();
		}

	}
        
	// Event fired whenever a packet is received.
	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len)
	{


		DataPacket* dpkt1 = (DataPacket*)(call Packet.getPayload(&pkt, sizeof(DataPacket)));

		if(dpkt1->type == 1 && TOS_NODE_ID != 0){

			if(dpkt1->dat != prev){
				count++;
				printfflush();
				printf("%u\n",count);
				printfflush();
			}


			prev = count;
			return msg;
		}

		if(call AMPacket.source(msg) == 99)// RBS packet
		{
			RBSPacket* rbspkt = (RBSPacket*)payload;

			//fill buffer with old entry
			last_rbs_buf[rbs_buf_pointer] = last_rbs_recp_time;
			rbs_buf_pointer++;

			if(rbs_buf_pointer == RBS_BUF_LEN) 
				rbs_buf_pointer = 0;
			
			//set new entry 
			last_rbs_pkt_id = rbspkt->packetid; 
			last_rbs_recp_time = call LocalClock.getNow();
			call Leds.led2Toggle();
		}
		else if (error_rate < generate_random()) //The error rate is smaller than the probability so the packet is acceptable.
		{
			SyncPacket* syncpkt = (SyncPacket*)payload;
			uint32_t T4 ;

			if (TOS_NODE_ID == 0 && isMyChild(call AMPacket.source(msg)) ) //I m root && the packet is from my child
			{
				SyncPacket* syncpkt2 = (SyncPacket*)(call Packet.getPayload(&pkt, sizeof(SyncPacket)));

				call Leds.set(0x07);
				call Leds.led0Toggle();

				if (syncpkt2 == NULL) {
					printf ("NULL returned\n");
					printfflush();
					return msg;
				}

				//Creates a packet to reply to the child from where the packet has came. Include T2, T3 in the packet.
				syncpkt2->T1 = syncpkt->T1;
				syncpkt2->T2 = call LocalClock.getNow();
				syncpkt2->T3 = call LocalClock.getNow();
				syncpkt2-> ROOT_RBS_PKT_ID =  last_rbs_pkt_id;
				syncpkt2-> ROOT_RBS_RECP_TIME =  last_rbs_recp_time;
				syncpkt2-> offset = 0;
				syncpkt-> type = 0;

				setTransmitChannel();



				// Sends the packet to the child.
				if (call AMSend.send(call AMPacket.source(msg), &pkt, sizeof(SyncPacket)) == SUCCESS) {
				}



				// "print local clock"
				tnow1 = call LocalClock.getNow();
				printf("%ld\n",tnow1);
				printfflush();
				call Leds.led0Toggle();

			}
			else // I m not root
			{

				if ( isMyChild(call AMPacket.source(msg)) ) //The packet is from my child 
				{

					SyncPacket* syncpkt2 = (SyncPacket*)(call Packet.getPayload(&pkt, sizeof(SyncPacket)));

					if (syncpkt2 == NULL) {
						printf ("NULL returned\n");
						printfflush();
						return msg;
					}

					//Construct packet to reply to the child. Include T2,T3.
					syncpkt2->T1 = syncpkt->T1;
					syncpkt2->T2 = call LocalClock.getNow();
					syncpkt2->T3 = call LocalClock.getNow();
					syncpkt2-> ROOT_RBS_PKT_ID =  root_rbs_pkt_id;
					syncpkt2-> ROOT_RBS_RECP_TIME =  root_rbs_recp_time;
					syncpkt2-> offset = total_offset_tpsn;
					syncpkt-> type = 0;

					// switch to transmit
					setTransmitChannel();



					//Sends the reply packet to the child node.
					if (call AMSend.send(call AMPacket.source(msg), &pkt, sizeof(SyncPacket)) == SUCCESS) {}

	
				}
				else if (isMyParent (call AMPacket.source(msg))) //The packet is from my parent
				{
					T4 = call LocalClock.getNow();
					root_rbs_recp_time = syncpkt->ROOT_RBS_RECP_TIME;
					root_rbs_pkt_id = syncpkt->ROOT_RBS_PKT_ID;
					CalculateDelta(syncpkt->T1,syncpkt->T2,syncpkt->T3,T4,syncpkt->offset);
				}
				else //Interferance packet
				{
				}
				
		
			}	
		}
		else //The packet is dropped.
		{
			printf ("PACKET DROPPED\n");
			printfflush();
		}
		return msg; 	
	}

	//Calculates TPSN offset, RBS offset and timesync error.
	void CalculateDelta(uint32_t T1,uint32_t T2,uint32_t T3,uint32_t T4, uint32_t offset_prop)
	{
		uint32_t tnow;

		// "offset calculation"
		offset_tpsn = ( (int32_t)(T2 - T1) - (int32_t)(T4 - T3) )/2;

		// "propagation delay"
		prop_delay =  ( (int32_t)(T2 - T1) + (int32_t)(T4 -T3) )/2;

		//printf("T1->T4 => (%ld , %ld , %ld , %ld)\n", T1,T2,T3,T4);

		// "total offset = prop_delay + offset"
		total_offset_tpsn = offset_tpsn + offset_prop;

		
		if(root_rbs_pkt_id == last_rbs_pkt_id)//check if same rbs packet
		{
			 offset_rbs = root_rbs_recp_time - last_rbs_recp_time;
		}
		else if(last_rbs_pkt_id > root_rbs_pkt_id && (last_rbs_pkt_id - root_rbs_pkt_id )<= RBS_BUF_LEN) 
		//Situation can be handled by buffer strategy: I have the more recent RBS than root and I have enough history saved in the buffer.
		{
			int32_t pos;

			//Fetch the corresponding RBS recp time value from the buffer.	
			pos = rbs_buf_pointer - (last_rbs_pkt_id - root_rbs_pkt_id);
			if(pos < 0)
				pos = pos + RBS_BUF_LEN;
			if(last_rbs_buf[pos] != 0)
				offset_rbs = root_rbs_recp_time - last_rbs_buf[pos] ;
		}
		else //Situation can't be handled by buffer strategy: root has more recent RBS than me or not enough buffer.
		{
		}

		//Finally calculates the total TPSN offset, and gives the error of the TPSN and RBS offset.
		//printf("%u %ld %ld %ld %lu\n", TOS_NODE_ID,total_offset_tpsn, offset_rbs,offset_rbs-total_offset_tpsn,time2sync);
		tnow = call LocalClock.getNow();
		//printf("%ld - %ld \n", offset_tpsn, prop_delay );
		//printf("%ld + %ld , Tnew : %ld \n",tnow,offset_tpsn,tnow + offset_tpsn - prop_delay);
		printfflush();
		time2sync = 0;
	}

	event void CC2420Config.syncDone(error_t error) {}

}
