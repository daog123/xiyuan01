#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <sys/mman.h>
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec*1e-9;}
int main(int argc,char **argv){
    if(argc!=4)return 2;
    int seconds=atoi(argv[2]);if(seconds<10||seconds>120)return 2;
    int fd=open(argv[1],O_RDONLY|O_SYNC);if(fd<0)return 3;
    volatile uint32_t *r=mmap(NULL,4096,PROT_READ,MAP_SHARED,fd,0);if(r==MAP_FAILED)return 4;
    if(r[0]!=0xe1e1c113)return 5;
    FILE *f=fopen(argv[3],"w");if(!f)return 6;
    setvbuf(f,NULL,_IOFBF,65536);
    fprintf(f,"# seconds,raw_done,raw_init,raw_link\n");
    double start=now(),elapsed=0;unsigned count=0,edges=0,last=r[3]&1;
    struct timespec delay={0,500000};
    while((elapsed=now()-start)<seconds){
        uint32_t done=r[3],init=r[2],link=r[4];
        fprintf(f,"%.9f,0x%08x,0x%08x,0x%08x\n",elapsed,done,init,link);
        if((done&1)!=last){edges++;last=done&1;}count++;nanosleep(&delay,NULL);
    }
    fclose(f);munmap((void*)r,4096);close(fd);
    printf("DONE_SAMPLES_CAPTURED seconds=%.3f samples=%u edges=%u\n",elapsed,count,edges);return 0;
}
