#define _GNU_SOURCE
#define _FILE_OFFSET_BITS 64
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <time.h>
#include <errno.h>

/* Bounded, volatile 9P programming using the supplied C6 SDK register sequence.
 * Arguments are verified private device nodes for PCI 0000:84:00.0.
 * Never accesses the persistent flash-update register window at 0x10000.
 */
static void delay_ms(long n){struct timespec t={n/1000,(n%1000)*1000000};nanosleep(&t,NULL);}
int main(int argc,char **argv){
    setvbuf(stdout,NULL,_IOLBF,0);
    if(argc!=5){fprintf(stderr,"usage: target_user target_h2c target_c2h reference.bit\n");return 2;}
    FILE *f=fopen(argv[4],"rb");if(!f){perror("bitstream");return 3;}
    if(fseek(f,0,SEEK_END))return 3;
    long len=ftell(f);rewind(f);
    if(len<1000000 || len>100000000){fprintf(stderr,"unexpected bitstream length\n");return 3;}
    size_t padded=((size_t)len+31)&~(size_t)31;
    unsigned char *buf=NULL;if(posix_memalign((void**)&buf,4096,padded))return 4;
    memset(buf,0,padded);if(fread(buf,1,(size_t)len,f)!=(size_t)len)return 4;fclose(f);
    if((!memmem(buf,260,"app_shell_9p_wrapper",20) && !memmem(buf,260,"array_selftest_top",18)) || !memmem(buf,260,"xcvu9p_CIV-flgb2104-2-i",23)){
        fprintf(stderr,"unexpected reference bitstream metadata\n");free(buf);return 5;
    }
    /* Match the actual CIV configuration target before touching the board. */
    const unsigned char id_packet[]={0x30,0x01,0x80,0x01,0x04,0xb3,0x50,0x93};
    const unsigned char sync[]={0xaa,0x99,0x55,0x66};
    unsigned char *sync_at=memmem(buf,4096,sync,sizeof sync);
    if(!sync_at || !memmem(sync_at,4096,id_packet,sizeof id_packet)){
        fprintf(stderr,"CIV IDCODE packet missing; refusing hardware access\n");free(buf);return 5;
    }
    int u=open(argv[1],O_RDWR|O_SYNC);if(u<0){perror("user open");return 6;}
    volatile uint32_t *reg=mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_SHARED,u,0);
    if(reg==MAP_FAILED){perror("user map");return 6;}
    if(reg[0]!=UINT32_C(0xe1e1c113)){fprintf(stderr,"management firmware changed\n");return 6;}
    printf("VOLATILE_PROGRAM_BEGIN file=%s bytes=%ld padded=%zu initial_done=%08x initial_link=%08x\n",argv[4],len,padded,reg[3],reg[4]);
    int h=open(argv[2],O_RDWR);if(h<0){perror("h2c open");return 7;}
    if(lseek(h,(off_t)UINT64_C(0x100000000),SEEK_SET)!=(off_t)UINT64_C(0x100000000)){perror("DDR seek");return 7;}
    size_t off=0;
    while(off<padded){size_t chunk=padded-off;if(chunk>1024*1024)chunk=1024*1024;if(lseek(h,(off_t)(UINT64_C(0x100000000)+off),SEEK_SET)!=(off_t)(UINT64_C(0x100000000)+off))return 8;ssize_t n=write(h,buf+off,chunk);if(n!=(ssize_t)chunk){fprintf(stderr,"stage DMA failed offset=%zu actual=%zd errno=%d\n",off,n,errno);close(h);return 8;}off+=chunk;}
    close(h);printf("BITSTREAM_STAGED bytes=%zu\n",off);
    int rd=open(argv[3],O_RDWR);if(rd<0)return 8;
    if(lseek(rd,(off_t)UINT64_C(0x100000000),SEEK_SET)!=(off_t)UINT64_C(0x100000000))return 8;
    unsigned char *check=NULL;if(posix_memalign((void**)&check,4096,1024*1024))return 8;
    off=0;
    while(off<padded){size_t chunk=padded-off;if(chunk>1024*1024)chunk=1024*1024;if(lseek(rd,(off_t)(UINT64_C(0x100000000)+off),SEEK_SET)!=(off_t)(UINT64_C(0x100000000)+off))return 8;ssize_t n=read(rd,check,chunk);if(n!=(ssize_t)chunk || memcmp(check,buf+off,chunk)){fprintf(stderr,"staged data mismatch/read failure offset=%zu actual=%zd\n",off,n);return 8;}off+=chunk;}
    close(rd);free(check);free(buf);printf("BITSTREAM_STAGING_READBACK_PASS bytes=%zu\n",off);
    /* Same offsets/order as mimic_api.c program_fpga(), chipsel=1. */
    reg[1]=1;reg[1]=0;delay_ms(10);
    printf("DONE_AFTER_CLEAR=%08x\n",reg[3]);
    /* Length is words; the final partial word is zero-padded in staged DDR. */
    reg[4]=(uint32_t)((len+3)/4);reg[2]=1;
    reg[0]=2;reg[0]=1;delay_ms(100);
    int saw_done_low=(reg[3]&1)==0;
    printf("PROGRAM_ASSERTED done=%08x init=%08x saw_done_low=%d\n",reg[3],reg[2],saw_done_low);
    reg[0]=0;
    int ready=0;
    for(int i=0;i<40;i++){if(reg[2]!=0){ready=1;break;}delay_ms(100);}
    printf("INIT_OBSERVED ready=%d init=%08x done=%08x link=%08x\n",ready,reg[2],reg[3],reg[4]);
    int done=0;
    for(int i=0;i<80;i++){if((reg[3]&1)==1){done=1;break;}delay_ms(250);}
    printf("VOLATILE_PROGRAM_%s done=%08x link=%08x saw_done_low=%d volatile_only=true\n",done&&saw_done_low?"PASS":done?"DONE_HIGH_UNCONFIRMED":"FAIL",reg[3],reg[4],saw_done_low);
    if(done){reg[1]=1;reg[1]=0;}
    printf("FINAL_RAW_INIT=%08x DONE=%08x LINK=%08x\n",reg[2],reg[3],reg[4]);
    munmap((void*)reg,4096);close(u);return done&&saw_done_low?0:9;
}

