"""
A small example of using a multiprocessing vs multithreaded concurrent execution environment.

A few words about processes and threads and CPUs. Modern machines usually have several CPU cores that can execute actual instructions
in parallel of each other. In addition, each CPU core may have some "hyperthreading" capability to run several threads more or less
at the same time in parallel of each other. That means that, all in all, modern CPUs can run several sequences of instructions in parallel
in hardware at the same time.

Of course, this comes with challenges: concurrent / parallel programming is hard (see deadlocks, shared memory, etc). So it is not always easy to take
advantage of all this hardware. Another difficulty is that there are many concepts that are sometimes used a bit loosely and are different
but similar, which may confuse the user.

The first concept is concurrency vs. parallelism. Concurrency is having one core do several tasks switching quickly between them. So it
appears that the core does several tasks at the same time, but really it just keep switching between tasks: think of a bartender serving
several customers. By contrast, parallelism is having several tasks being truly executed at the same time, on different cores; think about
2 bartenders serving 2 clients at the same time; no context / task switch, which is great, but more resources needed for this approach.

It is important to use the right tool for the right problem. For an IO bound problem, ie the program is slow due to waiting for the network,
parallelism (adding more CPUs) will not help per se (i.e., the fact of using more physical cores on the task will not by itself help, since
CPU computations is not the limitation), but concurrency may help a lot (for example, by starting at once 10 https requests, and treating these
as the answers arrive, rather than treating each slow request one after the other). By contrast, for a CPU bound task where CPU operations
are the bottleneck, concurrency will likely not help at all or even make things worse, while parallelism (if well used) will help a lot.

Now, regarding threads vs processes. In Linux, the OS is scheduling tasks; these may be a single-threaded process, or one of several
threads within a process, this makes not big difference from the OS point of view. A couple differences though are that 1) processes
are a bit more heavyweight to start and stop than threads for the OS, 2) 2 distinct processes do not share memory, each prosess has its
own virtual memory address space, while 2 threads under the same process share the virtual memory address space. This means that processes
are well isolated, do not share memory, which is easier to think about and "safer". By contrast, threads share memory, which may make
them harder to program (to avoid read write conflicts), but may be a bit faster if there is a lot of shared memory operations in your algorithm.
You can think of processes as distinct, well isolated programs running independently of each other, and threads under the same process
as "bits of programs" that are not isolated and run with very tight coupling (sharing memory with each other).

The situation is made even more complex (and a bit confusing at first) when coming to Python. Python has processes and threads, but was designed
at a time when CPU with multiple cores and / or hyperthreading was not a common thing. So, the way the Python interpreter is implemented
is, as a legacy reason, not "very good" at using threads. More specifically, a given python program / process can have several threads, and these
threads can run concurrently, but not in parallel: for a given python process having several threads running in parallel, at a given time,
there is only a single thread that is allowed to run code. This is very much Python specific: in C++ or Rust or many other languages, several
threads under the same process can perfectly be allowed to run code in parallel. The mechanism enforcing this behavior in Python is the GIL
(Global Interpreter Lock). There is 1 GIL per Python process, and a thread needs to acquire this unique GIL and lock it before being allowed
to execute any code. The consequence is faster single threaded Python programs (no need to check during each interaction with an object that
the object is not being modified in another thread, because since the present thread is active, other threads are not), at the cost of being
able to execute threads in parallel.

What this means is that, in the specific case of Python, concurrency can be adressed with either threads (the preferred way usually) or processes
(this may be overkill), but parallelism can only be adressed with processes. So, to speed up an IO or network bound task, use concurrency (as you
should in any language) or multithreading (that is a bit more unusual), but to speed up a CPU bound task, you can in Python only use multiprocessing
(and this would not be the case in other languages). The thing is that, confusing enough, all of these methods share very alike patterns, API structures etc,
so be awake and on the look, and be aware that this is different from what you would observe in some other language!

PS: some python interpreters have removed the GIL, but these are not so common, and the "default" python interpreter does not seem to be
heading towards removing the GIL anytime soon; more room for confusion!

Let us summarize a bit:

- Processes: separate programs with separate virtual memory address spaces; a bit heavier than threads to start and stop, isolated, no shared
memory across them.
- Threads: some "sub programs" under one process that share the same virtual memory address space; a bit faster to start and stop than
processes, the memory is shared, no isolation.

- concurrency: having only 1 instruction executed at a time, but possibly switching between several tasks: 1 bartender serving 5 people; this
only help is there is a lot of waiting to do.
- parallelism: having several instructions executed at the same time: 5 bartenders serving 5 people; may be faster if there is no waiting
time in the different tasks being run, and all what takes time is doing CPU computations.

In Python (at least for the mainstream Interpreter), the GIL lets only 1 thread of a given process execute code at a given time, so python
threads are useful for concurrency but useless for parallelism; Python processes are useful for both, but if the problem is concurrent but
not parallel, it may be better to use threads.

Saying it with a small drawing, where "-" means that the CPU is doing some work, and "|" means that the CPU is waiting:

- Concurrent task:

Both on the same physical core:
CPU core 1 task 1    ---|       -----------         ------------|  --------
CPU core 1 task 2       -------|           ---------             -|

- Parallel task (though there is a lot of waiting, may be better use or resources to run concurrently on 1 core in this example):

CPU core 1 task 1  ---|||||||-----------|||||||||||--------|||------------
CPU core 2 task 1  ------------||||||||||||||||||||||||||||||||||||||||||--

At this point, we need to say a few extra words, as there is still another way to run things in parallel: "green" or "lightweight" threads.
While "normal" or "OS" or "heavyweight" threads are managed by the OS, "green" or "lightweight" threads are managed by a user library. The
consequence is that starting / stopping / switching between green threads is much faster and less resources demanding than doing the same
with an OS thread. The downside is that green threads cannot be used for taking advantage of several CPU cores in parallel. In Python, this
makes no difference anyways, due to the GIL making threaded parallelism impossible, but in other languages, this introduces another
possibility to tradeoff weight vs. capability.

With that said, let us show some examples!
"""

import asyncio
from concurrent.futures import ProcessPoolExecutor
from concurrent.futures import ThreadPoolExecutor
import time

# a small note: in all the following, we will use "modern" async, await, and executor syntaxes; it is though also possible to use
# the "older" more "traditional" thead and multiprocessing modules to write this in a more "old school" way.


async def some_wait_bound_function(input: int, time_start: float) -> int:
    print(f"start some wait bound operation, input {input} elapsed: {time.time()-time_start}s")
    await asyncio.sleep(input)
    print(f"done some wait bound operation, input {input} elapsed: {time.time()-time_start}s")
    return input


async def some_cpu_bound_function(input: int, time_start: float) -> int:
    print(f"start some cpu bound operation, input {input} elapsed: {time.time()-time_start}s")
    start_value = 0
    for i in range(int(1e8)):
        start_value += i
    print(f"done some cpu bound operation, input {input} elapsed: {time.time()-time_start}s")
    return input


def main_task_1():
    # only wait based
    print
    return 1


def main_task_2():
    # only cpu based


def

time_start = time.time()

asyncio.run(some_cpu_bound_function(1, time_start))

# TODO:
# what is a thread / a process for the OS / python / rust

# the really tricky thing is: we can actually use asyncio to run several OS threds / use different CPU / run
# python multiprocessing in parallel...
# import asyncio
# from concurrent.futures import ProcessPoolExecutor
#
# print('running async test')
#
# def say_boo():
#     i = 0
#     while True:
#         print('...boo {0}'.format(i))
#         i += 1
#
#
# def say_baa():
#     i = 0
#     while True:
#         print('...baa {0}'.format(i))
#         i += 1
#
# if __name__ == "__main__":
#     executor = ProcessPoolExecutor(2)
#     loop = asyncio.get_event_loop()
#     boo = loop.run_in_executor(executor, say_boo)
#     baa = loop.run_in_executor(executor, say_baa)
#
#     loop.run_forever()

# import asyncio
# import time
# from concurrent.futures import ThreadPoolExecutor
#
# def queryFoo():
#     time.sleep(2)
#     return "FOO"
#
# def queryBar():
#     time.sleep(4)
#     return "BAR"
#
# with ThreadPoolExecutor(max_workers=2) as executor:
#     foo = executor.submit(queryFoo)
#     bar = executor.submit(queryBar)
#     results = [foo.result(), bar.result()]
#
# print(results)

