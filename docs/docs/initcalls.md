# Initcalls

**Initcalls** are callbacks that run during kernel bootime in a specific
sequence.

KFS supports 2 levels of initcalls for now.

- early  
- device  

A special section called `.init_call` exists in the binary where
pointers to callbacks are saved. This section is split in two subsections
`.init_call.early` and `.init_call.device`. At a specific point where the
memory subsystem is initialized and interrupts enabled the function
`do_initcalls` exported by the `kernel` module is called.

    Memory layout of initcall sections in RAM:

    +----------------------------+
    | ...                        |
    |                            |
    | Other kernel/data sections |
    |                            |
    +----------------------------+
    
    |<--- .init_call.early section --->|
    
    +----------------------------+
    | __init_call_early_start -->|  <-- symbol marking start of early initcalls
    +----------------------------+
    | *func pointer to initcall1 |  <-- pointers to functions
    +----------------------------+
    | *func pointer to initcall2 |
    +----------------------------+
    | *func pointer to initcall3 |
    +----------------------------+
    | ...                        |
    +----------------------------+
    | __init_call_early_end ---->|  <-- symbol marking end of early initcalls
    +----------------------------+
    
    |<--- .init_call.device section --->|
    
    +----------------------------+
    | __init_call_device_start -->|
    +----------------------------+
    | *f pointer to device initcall1 |
    +----------------------------+
    | *f pointer to device initcall2 |
    +----------------------------+
    | ...                        |
    +----------------------------+
    | __init_call_device_end ---->|
    +----------------------------+
    
    | .init.text              -->|
    +----------------------------+
    | function 1                 |
    +----------------------------+
    | function 1                 |
    +----------------------------+
    | function 1                 |
    +----------------------------+
    | function 1                 |
    +----------------------------+
    | ...                        |
    +----------------------------+
    | .init.text end        ---->|
    +----------------------------+
    |<---   after these sections  --->|
    +----------------------------+
    | Memory marked as available |
    | for general use afterwards |
    +----------------------------+
    

This function uses the symbols that denote each subsection to calculate
how many callbacks are saved there, casts them to function pointers and
calls the functions. Addinitional checks after the callbacks can be performed
to see if the callbacks leave the system in a inconsistent state.

After all the calls are finished, the memory that contains the function pointers 
and the section that contains the functions can be freed since they will never be called again
and can be used as available memory.

As the system grows more types of initcalls will be added.


