# a small illustration of how to use icecream and loguru
# ie redirecting the ic output to the info of loguru, to help switching on and off

from icecream import ic
from loguru import logger

# redirect icecream output to loguru logger at info level
ic.configureOutput(prefix="", outputFunction=logger.info)

meaning_of_life = 42

ic("hello")
ic(meaning_of_life)

