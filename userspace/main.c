void _start() {
    asm("mov $10, %eax \n int $0x80\n");
    while (42) {}
}
