"""Print the keys of a dictionary as a tree structure."""


def _dict_keys(my_dict, list_path_in_dict: list, indent=4) -> None:
    """Print the keys structure of my_dict, in a tree format.

    This implementation uses a recursive method, so not too good for very
    deep key hierarchies, but for a few keys of depth this should be
    more than fine enough."""

    parent_tree_to_print = ""

    for _, is_last in list_path_in_dict:
        if not is_last:
            parent_tree_to_print += "|" + (indent - 1) * " "
        else:
            parent_tree_to_print += indent * " "

    keyval = list(my_dict.items())
    len_keyval = len(keyval)

    for index, (key, val) in enumerate(keyval):
        if isinstance(val, dict):
            parent_tree_to_print_key = parent_tree_to_print + "|-"
            new_list_path_in_dict = list(list_path_in_dict)
            new_list_path_in_dict.append((key, index == (len_keyval-1)))
            print(parent_tree_to_print_key + f" {key}")
            _dict_keys(val, new_list_path_in_dict)
        else:
            print(parent_tree_to_print + f"|- {key}")
            pass


def dict_keys_tree(my_dict):
    """Print the tree of dict keys in my_dict."""

    if not isinstance(my_dict, dict):
        raise ValueError(f"Argument must be a dict! Got {type(my_dict)} instead!")

    _dict_keys(my_dict, [], 4)


if __name__ == "__main__":
    # just a small example
    dict_in = {}
    dict_in["lvl1_1"] = {}
    dict_in["lvl1_2"] = "bla"
    dict_in["lvl1_1"]["lvl2_1"] = {}
    dict_in["lvl1_1"]["lvl2_1"]["bla"] = 0
    dict_in["lvl1_1"]["lvl2_1"]["blaaaa"] = 0
    dict_in["lvl1_1"]["lvl2_2"] = 1
    dict_in["lvl1_1"]["lvl2_3"] = {}
    dict_in["lvl1_1"]["lvl2_3"]["lvl3_1"] = 0
    dict_in["lvl1_1"]["lvl2_3"]["lvl3_2"] = 0
    dict_in["lvl1_1"]["lvl2_3"]["lvl3_3"] = 0
    dict_in["lvl1_1"]["lvl2_3"]["lvl3_4"] = 0
    dict_in["lvl1_1"]["lvl2_3"]["lvl3_5"] = 0

    dict_keys_tree(dict_in)
