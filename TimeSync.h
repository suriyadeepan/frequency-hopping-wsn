#ifndef TIMESYNC_H
#define TIMESYNC_H
#define RBS_BUF_LEN 5
#define NODES_COUNT 5
enum {
	AM_BLINKTORADIO = 6,
};

//ith entry defines the parent of the node id 'i'.
int topology_array [NODES_COUNT] = {0,0,1,1,2};

//error rate for the whole network.
long double error_rate = 0;

//Time interval between two successive timesync request.
uint32_t pulse = 10000;

//TPSN Packet structure- 
//T1,T2,T3,T3: local time required in TPSN protocol.
//ROOT_RBS_PKT_TIME: Root local time when RBS pkt ID received by root.
//offset: TPSN offset between parent and root.
typedef nx_struct SyncPacket {
	
	nx_uint32_t T1;
	nx_uint32_t T2;
	nx_uint32_t T3;
	nx_uint32_t ROOT_RBS_PKT_ID;
	nx_uint32_t ROOT_RBS_RECP_TIME;
	nx_int32_t offset;
	nx_int16_t type;

} SyncPacket;

//RBS packet structure.
typedef nx_struct RBSPacket {
	nx_uint32_t packetid;
	nx_int16_t type;
} RBSPacket;

typedef nx_struct DataPacket{
	nx_uint16_t dat;
	nx_int16_t type;
}DataPacket;


#endif
