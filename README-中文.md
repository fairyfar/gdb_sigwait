**让 GDB 在应用程序使用 sigwait 时也能捕获“Ctrl + C”。**

# 一、问题

`gdb`调试`Linux`应用程序进程时，可以使用`Ctrl+C`快捷键中断`gdb`，以继续执行`gdb`命令。

但是，如果应用程序使用`sigwait`来处理`SIGINT`信号，那么，以上操作将失效。被调试的应用程序拦截了`SIGINT`信号。

在`gdb`中执行`info handle SIGINT`命令，可以看到“Pass to program”状态是“No”，但是`gdb`根本无法捕获到`SIGINT`信号。

```
(gdb) info handle SIGINT
Signal        Stop      Print   Pass to program Description
SIGINT        Yes       Yes     No              Interrupt
```

# 二、相关的问题讨论

关于这个问题，有几个非常经典的讨论帖：

* [GDB: Ctrl+C doesn't interrupt process as it usually does but rather terminates the program](https://stackoverflow.com/questions/5857300/gdb-ctrlc-doesnt-interrupt-process-as-it-usually-does-but-rather-terminates-t)
* [Bug 9425 - When using "sigwait" GDB doesn't trap SIGINT. Ctrl+C terminates program when should break gdb.](https://sourceware.org/bugzilla/show_bug.cgi?id=9425)
* [Bug 9039 - GDB is not trapping SIGINT. Ctrl+C terminates program when should break gdb.](https://bugzilla.kernel.org/show_bug.cgi?id=9039)

# 三、测试用例

代码如下：

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

编译并使用`gdb`调试这个应用程序：

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

可以看到，当试图中断`gdb`时，直接导致了被调试应用程序退出，即，被调试应用程序在`gdb`之前拦截了`SIGINT`信号。

# 四、解决方法

## 4.1 思路

修改应用程序代码，增加调试辅助代码，并与`gdb`命令配合。

## 4.2 方法

首先，修改代码，变更后代码框架如下：

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

然后，重新编译并调试，过程如下：

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

可见，修改之后，按`Ctrl+C`会自动进入断点（Breakpoint 2）。

以上有两条起关键左右的`gdb`命令：

* `set g_enable_breakon_sigint = 1`设置标志变量，以避免应用程序执行正常退出逻辑。
* `b gdb_breakon_sigint`设置断点，目的是达到中断`gdb`的效果。

## 4.3 自动化脚本

以上代码只是一个Demo，实际使用还是有些麻烦，为此，我们还需要与`gdb`脚本配合以实现自动化。

首先，编写一个`gdb`脚本，文件名为`sighandler.gdb`，脚本见工程目录：

```
gdb_sigwait/src/sighandler.gdb
```

然后，在`gdb`初始化文件（`~/.gdbinit`）中`source`上述脚本，例如：

```
source ~/gdb_sigwait/src/sighandler.gdb
```

# 五、附注

本项目使用MIT开源协议。

Scripted by FairyFar. [www.200yi.com](http://www.200yi.com)

