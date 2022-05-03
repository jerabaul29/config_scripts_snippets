from tqdm import tqdm

for i in tqdm(range(10000)):
    pass

dict_in = {}
dict_in_size = 50
for i in range(dict_in_size):
    dict_in[i] = "blabla"

for ind, elem in tqdm(enumerate(dict_in), total=dict_in_size):
    pass
