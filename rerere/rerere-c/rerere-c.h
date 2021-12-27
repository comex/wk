static inline void blackBoxImpl(const void *ptr) {
    asm volatile("" :: "r"(ptr) : "memory");
}
