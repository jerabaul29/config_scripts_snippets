import time
import asyncio
from typing import NoReturn

"""A small hello world for asyncio async await

The idea here is to show "how to think about async await". I like to have the following mental model:
- in Python, "usual" async await allows to get concurrency within a single thread; i.e., switch between different slow
tasks (when we know that something is slow and that we may do something else in the meantime), using only 1 CPU on the
physical machine. This is like having 1 bartender, serving several clients in the pub.
- i.e. this is very useful for using 1 OS thread / 1 machine physical CPU for doing several slow tasks
concurrently, i.e. switching between these tasks to make all of them advance as fast as possible together,
even though each task may have some forced waiting time now and then (you do not serve a new beer to a
client before the ongoing beer is drunk finished).
- i.e., in python, "usual" async await asyncio is a way to share a thread / machine CPU time between several
concurrent tasks.
- for this, one needs to:
-- "schedule" some tasks with asyncio.create_task or similar
-- give asyncio the chance to switch between tasks; this is done through the await keyword; when hitting
an await keyword, if the corresponding function call is not ready yet, the asyncio runner is free to look
for / jump to other async tasks and spend time on these
-- be CAREFUL not to use non-async (i.e. blocking) slow functions when trying to formulate some async code: these do not get
awaited and cannot give time for the runner to do anything else asyncronously.

The async keyword "adds some syntaxic sugar to make this function return a future".
The await keyword says to the asyncio executor to "feel free to attend other futures, somewhere else in the code, while this thing
resolves and gets ready". In practise, when an await function call is hit, the async executor is free to jump to another await
call and process it while the first call is resolving, before coming back to the initial await location.
The program will not progress past a given await call before it is fully resolved, but may do some other useful tasks (like, resolving
other awaits), while waiting for the initial await call to resolve.
Be sure to hit the await keyword often, and that all potentially lenghty calls are behind an await.
The async await model of python is well adapted for concurrency, ie code with slow io / network / database access, but not for cpu
intensive tasks.

So the whole async / await system is here to make it easier to work with futures that are used under the hood.
"""


def print_hello() -> NoReturn:
    """A non async hello world function cannot be called with an await
    keyword."""
    time.sleep(0.5)
    print("hello")


async def async_print_hello(time_start: float) -> int:
    """An async hello world function can be called with an await keyword,
    but if it makes no await call to slow async functions, this will not give
    us any gain and is not very helpful."""
    print(f"start async hello without internal awaitable awaited calls, elapsed: {time.time() - time_start}s")
    time.sleep(0.5)
    print(f"done async hello without internal awaitable awaited calls, elapsed: {time.time() - time_start}s")
    return 0


async def slow_function(input: int, time_start: float) -> int:
    """A slow function, for which the slow operations are provided with a future API,
    through asyncio calls or our own future-returning code, and are called as await, will be executed asyncronously
    in an effective way in the context of asyncio."""
    print(f"start slow_function with input {input}, elapsed: {time.time() - time_start}s")
    await asyncio.sleep(input)
    print(f"done waiting slow_function with input {input}, elapsed: {time.time() - time_start}s")
    return input


async def main_async() -> NoReturn:
    time_start = time.time()

    print(f"*** start scheduling some slow functions, elapsed: {time.time()-time_start}s")
    task_1 = asyncio.create_task(slow_function(1, time_start))
    task_2 = asyncio.create_task(slow_function(2, time_start))
    task_3 = asyncio.create_task(slow_function(3, time_start))
    task_4 = asyncio.create_task(slow_function(4, time_start))
    print(f"*** all slow functions scheduled, elapsed: {time.time()-time_start}s")
    # at this step, we have "scheduled" the async tasks, but never got the time to start executing code in them

    # none of the following 2 commands will work: cannot await a function, neither a result, need to (under the hood)
    # await a future (possibly created for us by declaring a function as async)
    # await print_hello
    # await print_hello()

    # we await a function without any await on awaitable call within itself, so there will not be ways for the asyncio runner
    # to look at other tasks and we get no gains
    await async_print_hello(time_start)

    # calling an async function directly without scheduling it as a task or awaiting it is an error and the corresponding
    # function will never get executed
    # slow_function(5, time_start)

    # we never hit an await where we actually had something to await for until now, and will not look for executing other
    # tasks until we do so; for example, this will not let us do any progress on our async tasks for now
    print("*** do something slow sync, that does not await (i.e. cannot wait)")
    time.sleep(1.5)
    print(f"*** done something slow sync, elapsed: {time.time()-time_start}s")

    # now we finally do hit an await, on something that does has some slow awaitable parts,
    # so asyncio will try to execute as many async tasks as possible
    # concurrently, jumping between "non ready" await calls in its own smart way :)
    print("*** do something slow async")
    await asyncio.sleep(1.5)
    print(f"*** done something slow async, elapsed: {time.time()-time_start}s")

    # one way to run all the tasks async
    # rest_1, res_2, res_3, res_4 = await asyncio.gather(task_1, task_2, task_3, task_4)

    # another way, using list and unpacking, that may be more elegant
    list_tasks = [task_1, task_2, task_3, task_4]
    # if we do not await here, we will get an error since we exit the function given to asyncio.run without await-ing that
    # all tasks are ready: i.e. need to await all tasks and collect them before moving out of async
    # list_res = asyncio.gather(*list_tasks)
    list_res = await asyncio.gather(*list_tasks)
    print(f"*** done awaiting the gather, got results {list_res}, elapsed: {time.time()-time_start}s")

# the line under cannot be run: cannot await outside of async bloc or asyncio executor
# await main_async

# There are different kinds of executors, based on threads or processes; the default executor (if not specified) will be
# a concurrent.futures.ThreadPoolExecutor with some default settings; due to the Python GIL, this poses some limitations
# (the GIL means, that for a given Python process, only one given thread can execute code at a time). There are other
# executors available (based on processes in particular), this is discussed in the asyncio_process_pool_executor examples.
# For now, let's use the default thread pool executor, and not care too much about the GIL :) .

# this will run the async function without problem: we explicitly ask asyncio to run tasks for us
# once this is done, the script will finish
asyncio.run(main_async())

# this is another way to do the same; this makes it clear that there is actually an asyncio "loop" running,
# that keeps checking for which async task can be performed every time an await is hit.
# once this is done, the script will finish
# loop = asyncio.get_event_loop()
# loop.run_until_complete(main_async())

# we can also force this asyncio loop to run forever: this script will then never finish, the asyncio loop will keep trying
# to find some async work to do, even if there is none; this is "like" the old way of having a main event loop looking for
# tasks / callbacks / work to do, again and again.
# loop = asyncio.get_event_loop()
# loop.create_task(main_async())
# loop.run_forever()

