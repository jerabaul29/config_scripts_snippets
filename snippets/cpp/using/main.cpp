#include "iostream"

using some_char_array = char[128];

int main(int argc, char const *argv[]){
    std::cout << "start" << std::endl;

    std::cout << sizeof(some_char_array) << std::endl;  // prints 128, the type is well the 128 bytes, not the pointer to the array

    std::cout << "end" << std::endl;

}