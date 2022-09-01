import pprint

pp = pprint.PrettyPrinter(indent=2)
pprintf = pp.pprint

dict_example = {}
dict_example["lvl1_1"] = 1
dict_example["lvl1_2"] = {}
dict_example["lvl1_2"][1] = 2
dict_example["lvl1_2"][2] = 3
dict_example["lvl1_2"][3] = 3
dict_example["lvl1_2"][4] = 3
dict_example["lvl1_2"][5] = 3
dict_example["lvl1_2"][6] = "my long long long long long long long string"
dict_example["lvl1_2"][7] = 3
dict_example["lvl1_2"][8] = 3

pprintf(dict_example)

