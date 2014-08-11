/* 
 * Copyright (C) 2014 David Vossel <dvossel@redhat.com>
 * 
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 * 
 * This software is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 */

#include <sys/param.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#include <stdlib.h>
#include <errno.h>
#include <fcntl.h>

#define OPTARGS	"f:"

static void
test_locking(const char *filepath)
{
    struct flock fl = {F_WRLCK, SEEK_SET, 0, 0, 0 };
    int fd;

    fl.l_pid = getpid();

    if ((fd = open(filepath, O_RDWR)) == -1) {
        perror("open");
        exit(1);
    }

    printf("Attempting to get write lock...\n");

    if (fcntl(fd, F_SETLKW, &fl) == -1) {
        perror("fcntl");
        close(fd);
        exit(1);
    }

    printf("LOCKED - %s\n", filepath);
    printf("Press <RETURN> to release lock: ");
    getchar();

    fl.l_type = F_UNLCK;
    if (fcntl(fd, F_SETLK, &fl) == -1) {
        perror("fcntl");
        close(fd);
        exit(1);
    }

    printf("UNLOCKED - %s\n", filepath);
    printf("success!\n");
    close(fd);
}

int
main(int argc, char **argv)
{
    int flag;
    const char *lockfile = NULL;

    while (1) {
        flag = getopt(argc, argv, OPTARGS);
        if (flag == -1)
            break;

        switch (flag) {
            case 'f':
                lockfile = optarg;
                break;
            default:
                printf("Unknown option: -%c\n", flag);
                break;
        }
    }

    if (lockfile) {
        test_locking(lockfile);
    } else {
        printf("ERROR: NO LOCK FILE GIVEN. usage: -f <lock file>\n");
    }


    return 0;
}
