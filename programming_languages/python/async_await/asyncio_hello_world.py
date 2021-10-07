import time
import asyncio


async def slow_function(input: int, time_start: float) -> int:
    print(f"start slow_function with input {input}, elapsed: {time.time() - time_start}s")
    await asyncio.sleep(input)
    print(f"done waiting slow_function with input {input}, elapsed: {time.time() - time_start}s")
    return input


async def main_async():
    time_start = time.time()

    print(f"*** start calling some slow functions, elapsed: {time.time()-time_start}s")
    task_1 = asyncio.create_task(slow_function(1, time_start))
    task_2 = asyncio.create_task(slow_function(2, time_start))
    task_3 = asyncio.create_task(slow_function(3, time_start))
    task_4 = asyncio.create_task(slow_function(4, time_start))
    print(f"*** all slow functions started, elapsed: {time.time()-time_start}s")
    # at this step, we have "scheduled" the async tasks, but never got the time to start executing code in them...

    # ... we never hit an await, so will not look for executing other tasks until we do so; for example, this will
    # not let us do any progress on our async tasks
    print("*** do something slow sync, that does not await (i.e. cannot wait)")
    time.sleep(1.5)
    print(f"*** done something slow sync, elapsed: {time.time()-time_start}s")

    # now we do hit an await, so asyncio will try to execute as many async tasks as possible
    print("*** do something slow async")
    await asyncio.sleep(1.5)
    print(f"*** done something slow async, elapsed: {time.time()-time_start}s")

    # one way to run all the tasks async
    # rest_1, res_2, res_3, res_4 = await asyncio.gather(task_1, task_2, task_3, task_4)

    # another way, using list and unpacking
    list_tasks = [task_1, task_2, task_3, task_4]
    # if we do not await here, we will get an error: need to await all tasks and collect them before moving out of async
    # list_res = asyncio.gather(*list_tasks)
    list_res = await asyncio.gather(*list_tasks)
    print(f"*** done awaiting the gather, got results {list_res}, elapsed: {time.time()-time_start}s")

# the line under cannot be run: cannot await outside of async bloc or asyncio executor
# await main_async

# this will run the async function without problem
asyncio.run(main_async())

# TODO:
# illustrate:
# loop = asyncio.get_event_loop()
# loop.run_until_complete(main())
#
# loop = asyncio.get_event_loop()
# loop.create_task(main())
# loop.run_forever()
#
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
