from icecream import ic

# ------------------------------------------------------------------------------------------
print("***** Configure icecream")
ic.configureOutput(prefix='', outputFunction=print)

meaning_of_life = 42

res = ic(meaning_of_life)
ic(res)

# for now the solution I know of for avoiding useless prints on return values in ipython3 is to use _ =
_ = ic(meaning_of_life)
