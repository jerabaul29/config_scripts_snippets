#include "iostream"

//////////////////////////////////////////////////////////////////////////////////////////
// no virtual
// this will just call the method "at the level where we are", in particular, no way
// to call derived method from a pointer to the object of base type.

class BaseClass {
    public:
        void say_hello(void) {
            std::cout << "Hello from base" << std::endl;
        }
};

// class DerivedClass : BaseClass {          // this is the same as:
// class DerivedClass : private BaseClass {  // which does not allow to have a pointer to base type pointing to derive
class DerivedClass : public BaseClass {      // this does allow to have a pointer to base type pointing to derive
    public:
        // this will mask the base class say_hello function; this is not idiomatic and not recommended!
        // in particular, calling say_hello on an object from a BaseClass or DerivedClass pointer will
        // call different functions...
        void say_hello(void) {
            std::cout << "Hello from derived" << std::endl;
        }
};

void example_no_virtual(void){

    std::cout << "No virtual" << std::endl;
    DerivedClass derived {};
    derived.say_hello();  // calls the derive hello method
    BaseClass * derived_as_base {&derived};
    derived_as_base->say_hello();  // calls the base hello method; no way to call the derive hello
    std::cout << std::endl;

}

//////////////////////////////////////////////////////////////////////////////////////////
// method calls with virtual
// a simple rule: use one and only one of "virtual", "override", "final" if working with a member function which should support virtual function call
// virtual on the "first" appearance of the function family line that should be virtual called
// override when intend to override
// final when should not be able to override further

class VirtualBaseClass {
    public:
        // this is fine, provide a default implementation
        // will be called if there is no overriding (with or without override keyword) in derived class
        /*
        virtual void say_hello(void) {
            std::cout << "Hello from base" << std::endl;
        }
        */

        // this is fine too, and maybe even clearer: the user HAS TO override in the derived class, no default implementation
        // in the base class
        virtual void say_hello(void)=0;
        virtual void say_goodbye(void)=0;
};

class OverrideDerivedClass : public VirtualBaseClass {  // need the public to be able to take a base pointer to the derived class
    public:

        // this will override the base class virtual say_hello function; this is idiomatic and ok
        // any call to say_hello, either from a VirtualBaseClass or a OverrideDerivedClass pointer,
        // will call this specific say_hello
        // void say_hello(void) {  // this is maybe less clear than what comes after: we still override a virtual function, we just dont tell... but it works too
        void say_hello(void) override {  // this is very clear: we override a virtual function; will raise compiler error if not actually overriding
            std::cout << "Hello from derived" << std::endl;
        }

        // same, except that this is now final: there is no way one can override at one more level!
        void say_goodbye(void) final {
            std::cout << "Goodbye (final) from derived" << std::endl;
        }
};

class Override2DerivedClass : public OverrideDerivedClass {
    public:

        // by now, you know the drill
        void say_hello(void) override {  // this overrides all the way, because the "root" two levels down was override
            std::cout << "Hello from double derived" << std::endl;
        }

        // this will not compile: cannot override a final from the previous depth!
        /*
        void say_goodbye(void) override{
            std::cout << "Goodbye from double derived" << std::endl;
        }
        */
};

void example_with_virtual(void){

    std::cout << "With virtual" << std::endl;
    Override2DerivedClass obj_virtual_2derived {};
    obj_virtual_2derived.say_hello();  // calls the derive hello method
    obj_virtual_2derived.say_goodbye();  // calls the derive goodbye method
    OverrideDerivedClass * obj_virtual_derived {&obj_virtual_2derived};
    obj_virtual_derived->say_hello();
    obj_virtual_derived->say_goodbye();
    VirtualBaseClass * obj_base {&obj_virtual_2derived};
    obj_base->say_hello();  // we override, so this calls the derived hello method
    obj_base->say_goodbye();  // we override, so this calls the derived goodbye method
    // obj_base->VirtualBaseClass::say_hello();  // that will not work, as it was =0, but the error will be at runtime, not compile time...
    obj_virtual_2derived.OverrideDerivedClass::say_hello();  // that will work: call explicitly a give non =0 method, so we bypass all the virtual stuff
    obj_virtual_derived->OverrideDerivedClass::say_hello();  // idem
    std::cout << std::endl;

}

//////////////////////////////////////////////////////////////////////////////////////////
// some tricks and tips: hiding / unhiding of methods
// there is an "unintuitive" hiding of functions with same name but different signature when inheriting
// the way around is with the "using" keyword!

class Base {
    public:
        void f(int value){
            std::cout << "Base f(int) " << value << std::endl;
        }
};

class DerivedNoUsing: public Base {
    public:
        void f(double value){
            std::cout << "derivedNoUsing f(double) " << value << std::endl;
        }
};

class DerivedUsing: public Base {
    public:
        using Base::f;  // un-hide the f(int)

        void f(double value){
            std::cout << "derivedUsing f(double) " << value << std::endl;
        }
};

class DerivedRedefine: public Base {
    public:
        void f(double value){
            std::cout << "derivedUsing f(double) " << value << std::endl;
        }

        void f(int value){  // another method for doing the same: explicitly re-define, by merely cally Base::f(int)
            Base::f(value);
        }
};

class VirtualBase {
    public:
        virtual void f(int value){
            std::cout << "Base f(int) " << value << std::endl;
        }
};

class DerivedVirtualNoUsing: public VirtualBase {
    public:
        virtual void f(double value){
            std::cout << "derivedNoUsing f(double) " << value << std::endl;
        }
};

class DerivedVirtualUsing: public VirtualBase {
    public:
        using VirtualBase::f;  // un-hide the f(int)

        virtual void f(double value){
            std::cout << "derivedUsing f(double) " << value << std::endl;
        }
};

void example_with_hiding(void){
    std::cout << "With hiding" << std::endl;
    std::cout << "-- no virtual" << std::endl;

    DerivedNoUsing obj_derived_no_using {};
    obj_derived_no_using.f(1);  // calling the float method !! there is hiding !!
    obj_derived_no_using.f(2.5);

    DerivedUsing obj_derived_using {};
    obj_derived_using.f(1);  // calling the int method, thanks to the using that "de-hides"
    obj_derived_using.f(2.5);

    DerivedRedefine obj_derived_redefine {};
    obj_derived_using.f(1);  // calling the int method, thanks to the re-definition
    obj_derived_using.f(2.5);

    std::cout << "-- with virtual" << std::endl;

    DerivedVirtualNoUsing obj_derived_virtual_no_using {};
    obj_derived_virtual_no_using.f(1);  // calling the float method !! there is hiding !!
    obj_derived_virtual_no_using.f(2.5);

    DerivedVirtualUsing obj_derived_virtual_using {};
    obj_derived_virtual_using.f(1);  // calling the int method, thanks to the using that "de-hides"
    obj_derived_virtual_using.f(2.5);

    std::cout << std::endl;
}

//////////////////////////////////////////////////////////////////////////////////////////
// constructors with inheritance
// how to use the constructor of the base, in the derived?
// this is similar to the previous point actually :) using or re-definition and forwarding of arguments is the way to go

class BaseWConstructor {
    public:
        BaseWConstructor(int value) {
            std::cout << "call constructor with value " << value << std::endl;
        }
};

class DerivedWConstructor : public BaseWConstructor {
    using BaseWConstructor::BaseWConstructor;
};

void example_using_constructor(void) {
    std::cout << "With constructor" << std::endl;
    DerivedWConstructor obj_derived_constructor {1};
    std::cout << std::endl;
}


//////////////////////////////////////////////////////////////////////////////////////////
// actually running stuff

int main(int argc, char const *argv[])
{
    std::cout << "Start main" << std::endl << std::endl;

    example_no_virtual();
    example_with_virtual();
    example_with_hiding();
    example_using_constructor();

    return 0;
}
