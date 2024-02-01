[中文](README-中文.md) | [ENGLISH](README.md)

**Allows GDB catch "Ctrl + C" even when the application is using sigwait.**

# 1. Problem

When `gdb` is debugging a `Linux` application's process, you can use the `Ctrl+C` shortcut to interrupt `gdb` for interactive input of user `gdb` commands.

However, if the application uses `sigwait` to handle the `SIGINT` signal, then the above operation will not work. The application being debugged intercepted the `SIGINT` signal.

Do `gdb` command `info handle SIGINT` command in `gdb`. You can see that the "Pass to program" item is "No", but `gdb` can not catch the `SIGINT` signal at all.

```
(gdb) info handle SIGINT
Signal        Stop      Print   Pass to program Description
SIGINT        Yes       Yes     No              Interrupt
```

# 2. Related Issues

There are several very classic issues:

* [GDB: Ctrl+C doesn't interrupt process as it usually does but rather terminates the program](https://stackoverflow.com/questions/5857300/gdb-ctrlc-doesnt-interrupt-process-as-it-usually-does-but-rather-terminates-t)
* [Bug 9425 - When using "sigwait" GDB doesn't trap SIGINT. Ctrl+C terminates program when should break gdb.](https://sourceware.org/bugzilla/show_bug.cgi?id=9425)
* [Bug 9039 - GDB is not trapping SIGINT. Ctrl+C terminates program when should break gdb.](https://bugzilla.kernel.org/show_bug.cgi?id=9039)

# 3. Test Case

Demo code to reproduce the problem:

```c
/*
Compile command:
gcc sigwait_demo.c -g -o sigwait_demo
*/
#include <stdlib.h>
#include <stdio.h>
#include <signal.h>
#include <stdbool.h>

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
				printf("SIGINT arrived. Exit now.\n");
				return 0;
			default:
				printf("Unhandled signal [%d]\n", signal);
				break;
		}
	}

	return 0;
}
```

Compile the code, then debug the generated application with `gdb`:

```bash
[yz@localhost src]$ gcc sigwait_demo.c -g -o sigwait_demo
[yz@localhost src]$ gdb sigwait_demo
GNU gdb (GDB) Red Hat Enterprise Linux 7.6.1-110.el7
...
(gdb) r
Starting program: sigwait_demo 
^CSIGINT arrived. Exit now.
[Inferior 1 (process 8016) exited normally]
(gdb) 
```

When trying to interrupt `gdb`, it can be seen that  the debugged application exits directly. So, the debugged application intercepts the `SIGINT` signal before `gdb`.

# 4. The Solution

## 4.1 Ideas

Modify the application's source code slightly. Add some debugging auxiliary code and cooperate with the `gdb` commands.

## 4.2 Methods

First, modify the source code. The changed code framework is as follows:

```c
……
// flag variable for debuging
volatile bool g_enable_breakon_sigint = false;
// function for gdb breakpoint
void gdb_breakon_sigint()
{
	printf("A chance to break on SIGINT\n");
}
……
int main(int argc, char **argv)
{
	……
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
	……
}
```

Then, re-compile and debug it as follows:

```bash
[yz@localhost src]$ gcc sigwait_demo.c -g -o sigwait_demo
[yz@localhost src]$ gdb sigwait_demo
GNU gdb (GDB) Red Hat Enterprise Linux 7.6.1-110.el7
...
(gdb) b main
Breakpoint 1 at 0x400672: file sigwait_demo.c, line 28.

(gdb) r
Starting program: sigwait_demo 
Breakpoint 1, main (argc=1, argv=0x7fffffffe098) at sigwait_demo.c:28
28		sa.sa_flags = SA_RESTART;

(gdb) set g_enable_breakon_sigint = 1
(gdb) b gdb_breakon_sigint
Breakpoint 2 at 0x40062b: file sigwait_demo.c, line 15.

(gdb) c
Continuing.
^C
Breakpoint 2, gdb_breakon_sigint () at sigwait_demo.c:15
15		printf("A chance to break on SIGINT\n")
(gdb)
```

It can be seen that after the modification,  `Ctrl+C` will automatically enter the breakpoint (Breakpoint 2).

There are two key `gdb` commands above:

* `set g_enable_breakon_sigint = 1`: Sets the flag variable to avoid the application from executing graceful exit logic.
* `b gdb_breakon_sigint`: Sets a breakpoint, the purpose is to achieve the effect of interrupting `gdb`.

## 4.3 Auto Scripts

The above source code is just a demo, and it's a little troublesome to actually use. For this, we also need to work with the `gdb` script to achieve automation.

First, write a `gdb` script, the file name is `sighhandler.gdb`. The script file is in the project directory:

```
gdb_sigwait/src/sighandler.gdb
```

Then, `source` the above script file in the `gdb` initialization file (`~/.gdbinit`), for example:

```
source ~/gdb_sigwait/src/sighandler.gdb
```

Notice! There are several constraints to using this `gdb` script:

- Your `gdb` was built with `Python` extension.
- The debugged application must have the symbol library (corresponding to the `-g` parameter of `gcc`).

# 5. Notes

## 5.1 Other Problems 

The function `signalfd` has a similar problem with `sigwait`, and the above method also works.

## 5.2 Open Source License

This project is released under the MIT license.

Scripted by FairyFar. [www.200yi.com](http://www.200yi.com)

