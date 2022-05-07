/*
Compile command:
gcc signalfd_demo.c -g -o signalfd_demo
*/
#include <stdlib.h>
#include <stdio.h>
#include <signal.h>
#include <stdbool.h>
#include <sys/signalfd.h>
#include <unistd.h>

// flag variable for debuging
volatile bool g_enable_breakon_sigint = false;
// function for gdb breakpoint
__attribute__((noinline))
void gdb_breakon_sigint()
{
	printf("A chance to break on SIGINT\n");
}

int main(int argc, char **argv)
{
	sigset_t mask;
	int sigfd;
	struct signalfd_siginfo fdsi;
	ssize_t ss;

	sigemptyset(&mask);
	sigaddset(&mask, SIGINT);
	sigaddset(&mask, SIGTERM);

	// Block signals
	if (sigprocmask(SIG_BLOCK, &mask, NULL) == -1)
	{
		printf("Error on sigprocmask.\n");
		return 1;
	}

	// Create signal fd
	sigfd = signalfd(-1, &mask, 0);
	if (sigfd == -1)
	{
		printf("Error on signalfd.\n");
		return 1;
	}

	while (1)
	{
		// Wait for signals.
		ss = read(sigfd, &fdsi, sizeof(struct signalfd_siginfo));
		if (ss != sizeof(struct signalfd_siginfo))
		{
			printf("Error on read.\n");
			return 1;
		}

		// Process signal.
		switch (fdsi.ssi_signo)
		{
			case SIGTERM:
				printf("SIGTERM arrived. Exit now.\n");
				return 0;
			case SIGINT:
				// do not exit if flag is true.
				if (g_enable_breakon_sigint)
				{
					gdb_breakon_sigint();
					break;
				}
				printf("SIGINT arrived. Exit now.\n");
				return 0;
			default:
				printf("Unhandled signal [%d]\n", fdsi.ssi_signo);
				break;
		}
	}

	return 0;
}

