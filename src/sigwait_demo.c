/*
Compile command:
gcc sigwait_demo.c -g -o sigwait_demo
*/
#include <stdlib.h>
#include <stdio.h>
#include <signal.h>
#include <stdbool.h>

// flag variable for debuging
volatile bool g_enable_breakon_sigint = false;
// function for gdb breakpoint
__attribute__((noinline))
void gdb_breakon_sigint()
{
	printf("A chance to break on SIGINT\n");
}

void sighandler_func(int signal)
{
	printf("Handled signal [%d].\n", signal);
}

int main(int argc, char **argv)
{
	sigset_t ss;
	int signal;
	struct sigaction sa;
	sa.sa_flags = SA_RESTART;
	sa.sa_handler = sighandler_func;

	// Set signal handlers
	if (sigaction(SIGTERM, &sa, NULL) < 0)
	{
		printf("Error on sigaction SIGTERM.\n");
		return 1;
	}
	if (sigaction(SIGINT, &sa, NULL) < 0)
	{
		printf("Error on sigaction SIGINT.\n");
		return 1;
	}

	if (sigfillset(&ss) < 0)
	{
		printf("Error on sigfillset.\n");
		return 1;
	}

	while (1)
	{
		// Wait for signals.
		if (sigwait(&ss, &signal) != 0)
		{
			printf("Error on sigwait.\n");
			return 1;
		}

		// Process signal.
		switch (signal)
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
				printf("Unhandled signal [%d]\n", signal);
				break;
		}
	}

	return 0;
}

