#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <time.h>
int main(int argc,char **argv){
    if(argc!=2)return 2;
    int fd=open(argv[1],O_RDWR|O_SYNC);if(fd<0)return 3;
    volatile uint32_t *r=mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    if(r==MAP_FAILED)return 4;
    if(r[0]!=0xe1e1c113){fprintf(stderr,"unexpected management version\n");return 5;}
    r[3]=1;__sync_synchronize();struct timespec t={1,0};nanosleep(&t,NULL);
    r[3]=0;__sync_synchronize();t.tv_sec=2;nanosleep(&t,NULL);
    printf("POST_PROGRAM_SYSTEM_RESET_PASS version=%08x link=%08x done=%08x\n",r[0],r[4],r[3]);
    munmap((void*)r,4096);close(fd);return 0;
}
