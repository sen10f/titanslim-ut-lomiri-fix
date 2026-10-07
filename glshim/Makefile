# Cross-compile libglshim.so for aarch64 glibc (Ubuntu Touch rootfs). Needs clang + lld.
CC = clang
libglshim.so: glshim.c
	$(CC) --target=aarch64-linux-gnu -fPIC -shared -nostdlib -O2 -fuse-ld=lld -o $@ $<
clean:
	rm -f libglshim.so
