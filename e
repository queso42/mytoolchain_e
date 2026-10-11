[ALL  ]      /home/debian/crosstool-ng-1.29.0/.build/HOST-aarch64-linux-gnu/arm-linux-uclibceabi/buildtools/lib/gcc/arm-linux-uclibceabi/14.4.0/../../../../arm-linux-uclibceabi/bin/ld: libc/libc_so.a(w_acos.os): in function `__GI_acos':
[ALL  ]      w_acos.c:(.text+0x7c): undefined reference to `feraiseexcept'
[ALL  ]      /home/debian/crosstool-ng-1.29.0/.build/HOST-aarch64-linux-gnu/arm-linux-uclibceabi/buildtools/lib/gcc/arm-linux-uclibceabi/14.4.0/../../../../arm-linux-uclibceabi/bin/ld: libc/libc_so.a(k_standardl.os): in function `__kernel_standard_l':
[ALL  ]      k_standardl.c:(.text+0x2c): undefined reference to `feholdexcept'
[ALL  ]      /home/debian/crosstool-ng-1.29.0/.build/HOST-aarch64-linux-gnu/arm-linux-uclibceabi/buildtools/lib/gcc/arm-linux-uclibceabi/14.4.0/../../../../arm-linux-uclibceabi/bin/ld: k_standardl.c:(.text+0x3c): undefined reference to `fesetenv'
      collect2: error: ld returned 1 exit status
      make[1]: *** [libc/Makefile.in:77: lib/libc.so] Error 1
